//
//  SourceCollector.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

import SharedToolkit
import SwiftSyntax

/// Walks a module's syntax and records everything the generator needs:
/// injectable types and values, their providers, `@Injected` uses, and members
/// carrying `@injected` parameters.
///
/// One instance walks every file in the module in turn and accumulates into the
/// same records, because resolution is module-wide. Only the source-location
/// bookkeeping is per file.
///
/// Everything is decided from syntax alone — the collector never sees resolved
/// types. Isolation, conformances, and type identity are all taken as written,
/// which is precisely why `ZerkSettings.json` and `@Isolated<A>` have to exist.
final class SourceCollector: SyntaxVisitor {
    private(set) var types: [TypeRecord] = []
    private(set) var values: [InjectableValueRecord] = []
    private(set) var diagnostics: [CodegenDiagnostic] = []
    /// Declared type/protocol names in the module -> whether they are public.
    private(set) var moduleAccessLevels: [String: Bool] = [:]
    /// `@Injected` property annotations seen in the module.
    private(set) var injectedUses: [InjectedUseRecord] = []
    /// Initializers/methods carrying `@injected` parameter markers.
    private(set) var markedMembers: [MarkedMemberRecord] = []
    /// Injectable key -> the spelling to emit for it.
    ///
    /// Keys match with `any` stripped, but the generated file needs a spelling
    /// that is legal Swift, and only the author knows whether their key is an
    /// existential — `any` is illegal on a class or a struct, and Zerk resolves
    /// nothing, so it can never add one. When two declarations disagree the
    /// `any` spelling wins, since it is the one that is correct in both Swift 6
    /// and under `ExistentialAny`.
    private(set) var keyDisplayNames: [String: String] = [:]
    /// `@ZerkAlias` / `#ZerkAlias` declarations, which merge keys before
    /// resolution. See ``KeyAliases``.
    private(set) var aliasDeclarations: [AliasDeclaration] = []

    private let settings: ZerkSettings
    private var sourceFile: String = ""
    private var converter: SourceLocationConverter?
    private var typeStack: [TypeContext] = []

    init(settings: ZerkSettings = .default) {
        self.settings = settings
        super.init(viewMode: .sourceAccurate)
    }

    /// Isolation applied to a declaration that states none: the enclosing
    /// declaration's, or the ambient default from `ZerkSettings.json`.
    private var ambientIsolation: ProviderIsolation {
        typeStack.last?.isolation ?? settings.defaultActorIsolation
    }

    /// Rebuilds the line/column converter for the file being entered. Nothing
    /// is collected at this level.
    override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        converter = SourceLocationConverter(fileName: sourceFile, tree: node)
        return .visitChildren
    }

    /// Walks one parsed file. `path` is kept only so diagnostics can name it;
    /// records from every file accumulate into this same collector.
    func walk(_ sourceFile: SourceFileSyntax, path: String? = nil) {
        self.sourceFile = path ?? ""
        super.walk(sourceFile)
    }

    // MARK: - Type declarations
    //
    // The four kinds Zerk can register. Each pushes an isolation frame on entry
    // and pops it in `visitPost`, so members and nested types read the isolation
    // of whatever encloses them.

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        enter(node, typeKind: .classKind, isGeneric: node.genericParameterClause != nil)
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        _ = typeStack.popLast()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        enter(node, typeKind: .structKind, isGeneric: node.genericParameterClause != nil)
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        _ = typeStack.popLast()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        enter(node, typeKind: .actorKind, isGeneric: node.genericParameterClause != nil)
        return .visitChildren
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        _ = typeStack.popLast()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        enter(node, typeKind: .enumKind, isGeneric: node.genericParameterClause != nil)
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        _ = typeStack.popLast()
    }

    /// Resolves the declaration's isolation once, hands it to the collectors,
    /// then pushes it so members and nested declarations inherit it.
    private func enter(_ node: some DeclGroupSyntax,
                       typeKind: MarkedTypeKind,
                       isGeneric: Bool) {
        let isolation = resolveTypeIsolation(node)
        collectType(node, isolation: isolation)
        collectMarkedMembers(node, typeKind: typeKind, typeIsGeneric: isGeneric)
        reportInertAutoInjected(node)
        typeStack.append(
            TypeContext(
                name: node.declaredName,
                isolation: isolation,
                sweptValueMethod: node.attributes
                    .firstAttribute(named: "InjectableValues")
                    .map { statedValueMethod($0) ?? settings.valueInjectionMethod }
            )
        )
    }

    /// An `actor` constructs nonisolated regardless of what surrounds it: its
    /// synchronous initializer is nonisolated at entry (SE-0327). Everything
    /// else takes what it states, falling back to the enclosing declaration or
    /// the ambient default.
    private func resolveTypeIsolation(_ node: some DeclGroupSyntax) -> ProviderIsolation {
        let stated = statedIsolation(modifiers: node.modifiers, attributes: node.attributes)
        let location = self.location(for: Syntax(node))
        validateStatedIsolation(
            stated,
            modifiers: node.modifiers,
            attributes: node.attributes,
            location: location
        )

        if node.is(ActorDeclSyntax.self) {
            if case .globalActor(let name) = stated {
                diagnostics.append(CodegenDiagnostic(
                    severity: .error,
                    message: "'\(node.declaredName)' is an actor, so its construction is nonisolated and cannot be isolated to '\(name)'. Remove the isolation annotation; actor isolation applies to the actor's methods, not to building it.",
                    location: location
                ))
            }
            return .nonisolated
        }

        return stated.resolved(default: ambientIsolation)
    }

    /// `@Isolated<A>` is corrective, not declarative — it restates what the
    /// compiler already believes. Contradicting the real annotation means one
    /// of the two is wrong, and guessing which would generate code that does
    /// not compile.
    private func validateStatedIsolation(_ stated: StatedIsolation,
                                         modifiers: DeclModifierListSyntax?,
                                         attributes: AttributeListSyntax?,
                                         location: AttributeLocation) {
        guard let marker = attributes?.isolatedMarkerName else {
            return
        }

        if modifiers?.isNonisolated == true {
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: "@Isolated<\(marker)> contradicts the 'nonisolated' modifier on the same declaration.",
                location: location
            ))
            return
        }

        if let actor = attributes?.globalActorName, actor != marker {
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: "@Isolated<\(marker)> contradicts the '@\(actor)' annotation on the same declaration.",
                location: location
            ))
        }
    }

    /// Warns about `@autoinjected` on a declaration that is not a provider,
    /// where it silently does nothing.
    ///
    /// A warning rather than an error: the marker is inert here, not wrong, and
    /// the code still builds and behaves correctly. What it must not do is stay
    /// quiet — the whole point of marking is to state the resolution explicitly,
    /// so a mark that is being ignored is exactly the situation the developer
    /// wrote it to rule out.
    ///
    /// One warning per declaration, positioned at its first marked parameter:
    /// the reason is a property of the declaration, and the fix — mark it
    /// `@InjectableProviding`, or move the parameters — is the same for all of
    /// them.
    private func reportInertAutoInjected(_ node: some DeclGroupSyntax) {
        let typeName = node.declaredName
        let isInjectable = !node.attributes.attributes(named: "Injectable").isEmpty

        var initializerCount = 0
        var hasExplicitProvider = false
        for member in node.memberBlock.members {
            if let initializer = member.decl.as(InitializerDeclSyntax.self) {
                initializerCount += 1
                hasExplicitProvider = hasExplicitProvider
                    || initializer.attributes.hasAttribute(named: "InjectableProviding")
            } else if let function = member.decl.as(FunctionDeclSyntax.self) {
                hasExplicitProvider = hasExplicitProvider
                    || function.attributes.hasAttribute(named: "InjectableProviding")
            }
        }

        for member in node.memberBlock.members {
            let parameters: FunctionParameterListSyntax
            let isProvider: Bool
            let subject: String

            if let initializer = member.decl.as(InitializerDeclSyntax.self) {
                parameters = initializer.signature.parameterClause.parameters
                // A sole initializer is adopted implicitly, but only while the
                // type declares no provider of its own.
                isProvider = initializer.attributes.hasAttribute(named: "InjectableProviding")
                    || (!hasExplicitProvider && initializerCount == 1)
                subject = "this initializer"
            } else if let function = member.decl.as(FunctionDeclSyntax.self) {
                parameters = function.signature.parameterClause.parameters
                isProvider = function.attributes.hasAttribute(named: "InjectableProviding")
                    && function.modifiers.isStatic
                subject = "'\(function.name.text)'"
            } else {
                continue
            }

            // Contradictory on its face, and no reading of it is safe to guess.
            for parameter in parameters
            where parameter.attributes.hasAttribute(named: "autoinjected")
                && parameter.attributes.hasAttribute(named: "noninjected") {
                diagnostics.append(CodegenDiagnostic(
                    severity: .error,
                    message: "'\(parameter.secondName?.text ?? parameter.firstName.text)' is marked both @autoinjected and @noninjected. Keep the one you meant.",
                    location: location(for: Syntax(parameter))
                ))
            }

            guard let marked = parameters.first(where: {
                $0.attributes.hasAttribute(named: "autoinjected")
            }) else {
                continue
            }
            guard !isProvider || !isInjectable else {
                continue
            }

            let reason = isInjectable
                ? "\(subject) is not '\(typeName)'s provider. Mark it @InjectableProviding, or move the marked parameters to the provider."
                : "'\(typeName)' is not @Injectable, so it has no provider whose parameters Zerk resolves."

            diagnostics.append(CodegenDiagnostic(
                severity: .warning,
                message: "@autoinjected has no effect here: \(reason)",
                location: location(for: Syntax(marked))
            ))
        }
    }

    /// `@ZerkAlias typealias Persisting = Storing` — the alias and the type it
    /// names become one key.
    ///
    /// A generic typealias is rejected by the macro; skipping it here keeps the
    /// plugin from acting on something the macro already refused.
    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.attributes.hasAttribute(named: "ZerkAlias") else {
            return .skipChildren
        }
        guard node.genericParameterClause?.parameters.isEmpty ?? true else {
            return .skipChildren
        }

        let aliasKey = node.name.text
        aliasDeclarations.append(
            AliasDeclaration(
                keys: [aliasKey, node.initializer.value.normalizedTypeKey],
                aliasKey: aliasKey,
                location: location(for: Syntax(node))
            )
        )
        return .skipChildren
    }

    /// `#ZerkAlias<A, B, C>()` — every listed type is the same key.
    ///
    /// The macro's expansion is what proves the claim to the compiler; all the
    /// plugin needs is the list. Written without the trailing `()` the generic
    /// clause never reaches either of us, so there is nothing to collect and the
    /// macro reports it.
    override func visit(_ node: MacroExpansionDeclSyntax) -> SyntaxVisitorContinueKind {
        collectAlias(macroName: node.macroName.text,
                     arguments: node.genericArgumentClause,
                     syntax: Syntax(node))
        return .skipChildren
    }

    override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
        collectAlias(macroName: node.macroName.text,
                     arguments: node.genericArgumentClause,
                     syntax: Syntax(node))
        return .skipChildren
    }

    private func collectAlias(macroName: String,
                              arguments: GenericArgumentClauseSyntax?,
                              syntax: Syntax) {
        guard macroName == "ZerkAlias" else {
            return
        }
        let keys = (arguments?.arguments.map(\.argument) ?? []).map(\.normalizedTypeKey)
        guard keys.count >= 2 else {
            return
        }
        aliasDeclarations.append(
            AliasDeclaration(
                keys: keys,
                aliasKey: nil,
                location: location(for: syntax)
            )
        )
    }

    /// Protocols are recorded for their access level alone. A protocol is an
    /// injection *key*, never a provider, so its members are skipped.
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        moduleAccessLevels[node.name.text] = node.modifiers.isPublic
        return .skipChildren
    }

    /// A property may be an `@Injectable` value, an `@Injected` use, or a
    /// misuse of the `@injected` parameter marker. Children are skipped —
    /// nothing nested inside a property declaration can be any of those.
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        collectValue(node)
        collectInjectedUse(node)
        if node.attributes.hasAttribute(named: "injected") {
            diagnostics.append(
                CodegenDiagnostic(
                    severity: .error,
                    message: "@injected is a parameter marker and cannot be applied to a property. Use @Injected for properties.",
                    location: location(for: Syntax(node))))
        }
        if node.attributes.hasAttribute(named: "autoinjected") {
            diagnostics.append(
                CodegenDiagnostic(
                    severity: .error,
                    message: "@autoinjected is a provider-parameter marker and cannot be applied to a property. Use @Injected for properties.",
                    location: location(for: Syntax(node))))
        }
        return .skipChildren
    }

    /// Records one type's injectable keys and the providers that satisfy them.
    ///
    /// A type can be injectable under several keys at once, and `@Shared` and
    /// `@Injectable(primary:)` apply per key rather than per type, so all three
    /// are gathered as dictionaries keyed by type key.
    private func collectType(_ node: some DeclGroupSyntax, isolation typeIsolation: ProviderIsolation) {
        moduleAccessLevels[node.declaredName] = node.modifiers.isPublic

        let injectableAttributes = node.attributes.attributes(named: "Injectable")
        guard !injectableAttributes.isEmpty else { return }


        let sharedAttributes = node.attributes.attributes(named: "Shared")
        let isSingleton = node.attributes.hasAttribute(named: "Singleton")
        let location = self.location(for: Syntax(node))

        for attribute in injectableAttributes {
            if attribute.hasPositionalArgument {
                diagnostics.append(CodegenDiagnostic(
                    severity: .error,
                    message: "The injection method applies to values only. A type is built by a provider, not read from a declaration, so there is nothing to copy or reference.",
                    location: location
                ))
            }
            if attribute.primaryArgument == .nonLiteral {
                diagnostics.append(CodegenDiagnostic(
                    severity: .error,
                    message: "@Injectable(primary:) requires a 'true' or 'false' literal. Zerk reads this from source and cannot evaluate an expression.",
                    location: location
                ))
            }
        }

        if isSingleton && (node.is(StructDeclSyntax.self) || node.is(EnumDeclSyntax.self)) {
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: "@Singleton can only be applied to reference types (class or actor).",
                location: location
            ))
        }

        var injectableKeys: [String: AttributeLocation] = [:]
        for attribute in injectableAttributes {
            let genericKeys = attribute.genericArgumentKeys
            let keys = genericKeys.isEmpty ? [node.declaredName] : genericKeys
            // Paired with `keys` by index: the same types, canonicalized with
            // `any` kept. An unparameterized @Injectable keys on the type's own
            // name, which is a bare identifier either way.
            let displayKeys = genericKeys.isEmpty
                ? [node.declaredName]
                : attribute.genericArgumentDisplayKeys

            for (offset, key) in keys.enumerated() {
                injectableKeys[key] = location
                recordKeyDisplayName(displayKeys[offset], for: key)
            }
        }

        var sharedKeys: [String: AttributeLocation] = [:]
        for attribute in sharedAttributes {
            let genericKeys = attribute.genericArgumentKeys
            let keys = genericKeys.isEmpty ? Array(injectableKeys.keys) : genericKeys
            for key in keys {
                sharedKeys[key] = location
            }
        }

        // `@Injectable<A>(primary: true) @Injectable<B>` claims A only: primacy
        // rides on the attribute that names the key, not on the declaration.
        var primaryKeys: [String: AttributeLocation] = [:]
        for attribute in injectableAttributes where attribute.primaryArgument.isPrimary {
            let genericKeys = attribute.genericArgumentKeys
            let keys = genericKeys.isEmpty ? [node.declaredName] : genericKeys
            for key in keys {
                primaryKeys[key] = location
            }
        }

        var defaultProviders: [InjectingProvider] = []
        var typedProviders: [String: [InjectingProvider]] = [:]
        var initializers: [InitializerRecord] = []

        for member in node.memberBlock.members {
            if let initializer = member.decl.as(InitializerDeclSyntax.self) {
                let parameters = initializer.signature.parameterClause.parameters
                    .parameterRecords(locatedBy: { self.location(for: $0) })
                let effects = ProviderEffects(from: initializer.signature.effectSpecifiers?.trimmedDescription)
                let initializerLocation = self.location(for: Syntax(initializer))
                let initializerStated = statedIsolation(
                    modifiers: initializer.modifiers,
                    attributes: initializer.attributes
                )
                validateStatedIsolation(
                    initializerStated,
                    modifiers: initializer.modifiers,
                    attributes: initializer.attributes,
                    location: initializerLocation
                )
                let initializerIsolation = initializerStated.resolved(default: typeIsolation)
                initializers.append(
                    InitializerRecord(
                        parameters: parameters,
                        effects: effects,
                        location: initializerLocation,
                        isolation: initializerIsolation
                    )
                )

                for attribute in initializer.attributes.attributes(named: "InjectableProviding") {
                    if !attribute.genericArgumentKeys.isEmpty {
                        diagnostics.append(CodegenDiagnostic(
                            severity: .error,
                            message: "@InjectableProviding on an initializer cannot declare generic keys.",
                            location: initializerLocation
                        ))
                    }
                    if attribute.primaryArgument == .nonLiteral {
                        diagnostics.append(nonLiteralPrimaryDiagnostic(at: initializerLocation))
                    }
                    defaultProviders.append(
                        InjectingProvider(
                            kind: .initializer,
                            parameters: parameters,
                            effects: effects,
                            location: initializerLocation,
                            returnTypeName: nil,
                            isolation: initializerIsolation,
                            isPrimary: attribute.primaryArgument.isPrimary
                        )
                    )
                }
                continue
            }

            guard let function = member.decl.as(FunctionDeclSyntax.self) else {
                continue
            }
            guard function.modifiers.isStatic else {
                continue
            }

            let injectingAttributes = function.attributes.attributes(named: "InjectableProviding")
            guard !injectingAttributes.isEmpty else {
                continue
            }

            let returnType = function.signature.returnClause?.type.trimmedDescription ?? ""
            let functionLocation = self.location(for: Syntax(function))
            let functionStated = statedIsolation(
                modifiers: function.modifiers,
                attributes: function.attributes
            )
            validateStatedIsolation(
                functionStated,
                modifiers: function.modifiers,
                attributes: function.attributes,
                location: functionLocation
            )
            // One record per attribute rather than per function: `primary:` is a
            // claim about a single key, so a factory bound to two keys can be
            // primary for one of them and not the other.
            for attribute in injectingAttributes {
                if attribute.primaryArgument == .nonLiteral {
                    diagnostics.append(nonLiteralPrimaryDiagnostic(at: functionLocation))
                }

                let provider = InjectingProvider(
                    kind: .staticFunction(name: function.name.text),
                    parameters: function.signature.parameterClause.parameters
                        .parameterRecords(locatedBy: { self.location(for: $0) }),
                    effects: ProviderEffects(from: function.signature.effectSpecifiers?.trimmedDescription),
                    location: functionLocation,
                    returnTypeName: returnType.isEmpty ? nil : returnType,
                    isolation: functionStated.resolved(default: typeIsolation),
                    isPrimary: attribute.primaryArgument.isPrimary
                )

                let genericKeys = attribute.genericArgumentKeys
                if genericKeys.isEmpty {
                    defaultProviders.append(provider)
                    continue
                }

                for key in genericKeys {
                    typedProviders[key, default: []].append(provider)
                }
            }

            if returnType.isEmpty {
                diagnostics.append(CodegenDiagnostic(
                    severity: .error,
                    message: "@InjectableProviding functions must declare a return type.",
                    location: functionLocation
                ))
            }
        }

        if initializers.isEmpty, var inferredInitializer = node.inferredSynthesizedInitializer(in: location) {
            inferredInitializer.isolation = typeIsolation
            initializers.append(inferredInitializer)
        }

        types.append(
            TypeRecord(
                name: node.declaredName,
                injectableKeys: injectableKeys,
                sharedKeys: sharedKeys,
                primaryKeys: primaryKeys,
                defaultProviders: defaultProviders,
                typedProviders: typedProviders,
                initializers: initializers,
                isSingleton: isSingleton,
                isolation: typeIsolation
            )
        )
    }

    /// Records an `@Injectable` *value*: a static property registered so that
    /// parameters can be satisfied by a constant rather than by constructing a
    /// type.
    ///
    /// Requires one named binding with an explicit type annotation, since the
    /// key it registers under is that annotation and an inferred type cannot be
    /// recovered from syntax.
    /// Reads the `ValueInjectionMethod` from an attribute's first unlabeled
    /// argument. `nil` covers both "no argument" and an explicit `.default` —
    /// they mean the same thing, defer to settings.
    /// `primary:` decides which implementation ships, and it is read out of the
    /// source text rather than evaluated — so an expression Zerk cannot read
    /// would quietly resolve to "not primary" instead of failing.
    private func nonLiteralPrimaryDiagnostic(at location: AttributeLocation) -> CodegenDiagnostic {
        CodegenDiagnostic(
            severity: .error,
            message: "@InjectableProviding(primary:) requires a 'true' or 'false' literal. Zerk reads this from source and cannot evaluate an expression.",
            location: location
        )
    }

    private func statedValueMethod(_ attribute: AttributeSyntax) -> ValueInjectionMethod? {
        for argument in attribute.labeledArguments where argument.label == nil {
            guard let member = argument.expression.as(MemberAccessExprSyntax.self) else {
                continue
            }
            return ValueInjectionMethod(rawValue: member.declName.baseName.text)
        }
        return nil
    }

    /// Whether the declaration can be assigned through: a `var` that is stored,
    /// or computed with a setter. Observers (`willSet`/`didSet`) leave it
    /// stored, so those stay settable.
    private func isSettable(_ node: VariableDeclSyntax, binding: PatternBindingSyntax) -> Bool {
        guard node.bindingSpecifier.text == "var" else {
            return false
        }
        guard let accessors = binding.accessorBlock?.accessors else {
            return true
        }
        switch accessors {
        case .getter:
            // `var x: T { ... }` — computed, read-only.
            return false
        case .accessors(let list):
            return list.contains {
                let name = $0.accessorSpecifier.text
                return name == "set" || name == "willSet" || name == "didSet"
            }
        }
    }

    private func collectValue(_ node: VariableDeclSyntax) {
        let injectableAttributes = node.attributes.attributes(named: "Injectable")
        let sweptMethod = typeStack.last?.sweptValueMethod

        guard !injectableAttributes.isEmpty else {
            if let sweptMethod {
                collectSweptValue(node, method: sweptMethod)
            }
            return
        }

        guard let binding = node.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
              let annotation = binding.typeAnnotation else {
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: "@Injectable values must declare a single named binding with an explicit type.",
                location: location(for: Syntax(node))
            ))
            return
        }

        let typeName = annotation.type.trimmedDescription
        let genericKeys = injectableAttributes.flatMap(\.genericArgumentKeys)
        let keys = genericKeys.isEmpty ? [annotation.type.normalizedTypeKey] : genericKeys
        // Paired with `keys` by index, so a value keyed `any P` emits its `any`
        // just as a type-backed key does.
        let displayKeys = genericKeys.isEmpty
            ? [annotation.type.displayTypeKey]
            : injectableAttributes.flatMap(\.genericArgumentDisplayKeys)
        let bodyText = binding.initializer?.value.trimmedDescription ?? accessorBodyText(from: binding.accessorBlock)
        let valueLocation = location(for: Syntax(node))

        for attribute in injectableAttributes where attribute.primaryArgument != .absent {
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: "'primary' applies to types only. A value is the sole provider for its key, so there is nothing to be primary over.",
                location: valueLocation
            ))
        }

        let method = injectableAttributes.compactMap(statedValueMethod).first
            ?? sweptMethod
            ?? settings.valueInjectionMethod

        let stated = statedIsolation(modifiers: node.modifiers, attributes: node.attributes)
        validateStatedIsolation(
            stated,
            modifiers: node.modifiers,
            attributes: node.attributes,
            location: valueLocation
        )
        let isolation = stated.resolved(default: ambientIsolation)

        guard validateReferenceable(node, name: identifier.identifier.text, method: method, at: valueLocation) else {
            return
        }

        for (offset, key) in keys.enumerated() {
            recordKeyDisplayName(displayKeys[offset], for: key)
            values.append(
                InjectableValueRecord(
                    name: identifier.identifier.text,
                    typeKey: key,
                    typeName: typeName,
                    keyDisplayName: displayKeys[offset],
                    bodyText: bodyText,
                    location: valueLocation,
                    isolation: isolation,
                    injectionMethod: method,
                    enclosingTypePath: enclosingTypePath,
                    isSettable: isSettable(node, binding: binding)
                )
            )
        }
    }

    /// Records how a key should be spelled in the generated file, preferring an
    /// `any` spelling over a bare one when declarations disagree.
    ///
    /// Only `@Injectable` declarations feed this: they are what *establish* a
    /// key, and so what the `extension Zerk<Key>` is written as. A parameter or
    /// an `@Injected` property keeps its own spelling at its own use site, which
    /// reaches the same specialization regardless.
    private func recordKeyDisplayName(_ displayName: String, for key: String) {
        guard let existing = keyDisplayNames[key] else {
            keyDisplayNames[key] = displayName
            return
        }
        if !existing.hasPrefix("any ") && displayName.hasPrefix("any ") {
            keyDisplayNames[key] = displayName
        }
    }

    /// Dot-joined enclosing type names, or `nil` at file scope.
    private var enclosingTypePath: String? {
        typeStack.isEmpty ? nil : typeStack.map(\.name).joined(separator: ".")
    }

    /// A referenced value is read from the generated file, which is a different
    /// file in the same module, so anything narrower than `internal` is out of
    /// reach. Copied values are unaffected — their body is inlined, not read.
    private func validateReferenceable(_ node: VariableDeclSyntax,
                                       name: String,
                                       method: ValueInjectionMethod,
                                       at location: AttributeLocation) -> Bool {
        guard method == .referenced else {
            return true
        }
        let access = node.modifiers.accessRank
        guard access <= .fileprivate else {
            return true
        }
        diagnostics.append(CodegenDiagnostic(
            severity: .error,
            message: "'\(name)' is \(access.rawValue), so the generated file cannot reference it. Raise it to internal, or use .copied.",
            location: location
        ))
        return false
    }

    /// A member picked up by `@InjectableValues` rather than annotated
    /// individually.
    ///
    /// Members that cannot be injected are skipped rather than reported —
    /// marking a type is a statement about the type, not a promise that every
    /// member qualifies. The one exception is a missing type annotation, which
    /// almost always means the author expected the member to be injected: the
    /// type is the injection key and syntax alone cannot infer it.
    private func collectSweptValue(_ node: VariableDeclSyntax, method: ValueInjectionMethod) {
        guard !node.attributes.hasAttribute(named: "NonInjectable") else {
            return
        }
        guard node.modifiers.isStatic else {
            return
        }
        // Unreachable from the generated file; silently not part of the graph.
        guard node.modifiers.accessRank > .fileprivate else {
            return
        }
        guard let binding = node.bindings.first,
              node.bindings.count == 1,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
            return
        }

        let valueLocation = location(for: Syntax(node))

        guard let annotation = binding.typeAnnotation else {
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: "@InjectableValues needs an explicit type on '\(identifier.identifier.text)' — the type is the injection key, and Zerk reads syntax so it cannot infer one. Annotate it, or move the member out of the marked type.",
                location: valueLocation
            ))
            return
        }

        let stated = statedIsolation(modifiers: node.modifiers, attributes: node.attributes)
        validateStatedIsolation(
            stated,
            modifiers: node.modifiers,
            attributes: node.attributes,
            location: valueLocation
        )

        recordKeyDisplayName(annotation.type.displayTypeKey, for: annotation.type.normalizedTypeKey)

        values.append(
            InjectableValueRecord(
                name: identifier.identifier.text,
                typeKey: annotation.type.normalizedTypeKey,
                typeName: annotation.type.trimmedDescription,
                keyDisplayName: annotation.type.displayTypeKey,
                bodyText: binding.initializer?.value.trimmedDescription
                    ?? accessorBodyText(from: binding.accessorBlock),
                location: valueLocation,
                isolation: stated.resolved(default: ambientIsolation),
                injectionMethod: method,
                enclosingTypePath: enclosingTypePath,
                isSettable: isSettable(node, binding: binding)
            )
        )
    }

    /// Records `@Injected` properties so the generator can check the chain
    /// behind each one.
    ///
    /// `@Injected` expands to a synchronous, non-throwing accessor, so a chain
    /// that turns out async, throwing, or cross-domain has to be reported
    /// against the property rather than left to fail in generated code.
    private func collectInjectedUse(_ node: VariableDeclSyntax) {
        for macroName in ["Injected"] {
            let attributes = node.attributes.attributes(named: macroName)
            guard !attributes.isEmpty else {
                continue
            }
            guard let binding = node.bindings.first,
                  let annotation = binding.typeAnnotation else {
                continue
            }

            // `@Injected var service: Service?` injects a `Service` — the
            // optionality belongs to the property, not to the key. `?`, `!` and
            // `Optional<…>` are one canonical spelling by the time we get here,
            // so a single unwrap covers all three.
            var typeKey = annotation.type.normalizedTypeKey
            if typeKey.hasPrefix("Optional<"), typeKey.hasSuffix(">") {
                typeKey = String(typeKey.dropFirst("Optional<".count).dropLast())
            }

            for attribute in attributes {
                var namesMemberDirectly = false
                if case .argumentList(let arguments)? = attribute.arguments,
                   arguments.count == 1,
                   arguments.first?.label == nil,
                   arguments.first?.expression.is(KeyPathExprSyntax.self) == true {
                    namesMemberDirectly = true
                }
                injectedUses.append(InjectedUseRecord(
                    // `@Injected<Foo>` states the key; otherwise it is the
                    // property's own type.
                    typeKey: attribute.genericArgumentKeys.first ?? typeKey,
                    macroName: "@\(macroName)",
                    namesMemberDirectly: namesMemberDirectly,
                    location: location(for: Syntax(node))
                ))
            }
        }
    }

    // MARK: @injected parameter markers

    /// Finds initializers and methods carrying `@injected` parameters.
    ///
    /// An actor is recorded as nonisolated here: it has no global-actor
    /// spelling for Zerk to emit onto the generated overload, so its members
    /// carry `MarkedMemberIsolation.actorInstance` and inherit isolation from
    /// the extension instead.
    private func collectMarkedMembers(_ node: some DeclGroupSyntax,
                                      typeKind: MarkedTypeKind,
                                      typeIsGeneric: Bool) {
        let qualifiedName = (typeStack.map(\.name) + [node.declaredName]).joined(separator: ".")
        let typeAccess = node.modifiers.accessRank
        let isActorType = node.is(ActorDeclSyntax.self)
        let typeIsolation = isActorType
            ? ProviderIsolation.nonisolated
            : statedIsolation(modifiers: node.modifiers, attributes: node.attributes)
                .resolved(default: ambientIsolation)

        for member in node.memberBlock.members {
            if let initializer = member.decl.as(InitializerDeclSyntax.self) {
                collectMarkedMember(
                    parameters: initializer.signature.parameterClause.parameters,
                    kind: .initializer,
                    effects: ProviderEffects(from: initializer.signature.effectSpecifiers?.trimmedDescription),
                    memberIsGeneric: initializer.genericParameterClause != nil,
                    modifiers: initializer.modifiers,
                    typeName: qualifiedName,
                    typeKind: typeKind,
                    typeIsGeneric: typeIsGeneric,
                    typeAccess: typeAccess,
                    isolation: .explicit(statedIsolation(
                        modifiers: initializer.modifiers,
                        attributes: initializer.attributes
                    ).resolved(default: typeIsolation)),
                    location: location(for: Syntax(initializer))
                )
            } else if let function = member.decl.as(FunctionDeclSyntax.self) {
                let functionStatedIsolation = statedIsolation(
                    modifiers: function.modifiers,
                    attributes: function.attributes
                )
                let functionIsolation: MarkedMemberIsolation
                if isActorType,
                   !function.modifiers.isStatic,
                   functionStatedIsolation == .unstated {
                    functionIsolation = .actorInstance
                } else {
                    functionIsolation = .explicit(functionStatedIsolation.resolved(default: typeIsolation))
                }

                collectMarkedMember(
                    parameters: function.signature.parameterClause.parameters,
                    kind: .method(
                        name: function.name.text,
                        isStatic: function.modifiers.isStatic,
                        returnType: function.signature.returnClause?.type.trimmedDescription
                    ),
                    effects: ProviderEffects(from: function.signature.effectSpecifiers?.trimmedDescription),
                    memberIsGeneric: function.genericParameterClause != nil,
                    modifiers: function.modifiers,
                    typeName: qualifiedName,
                    typeKind: typeKind,
                    typeIsGeneric: typeIsGeneric,
                    typeAccess: typeAccess,
                    isolation: functionIsolation,
                    location: location(for: Syntax(function))
                )
            }
        }
    }

    /// Validates and records one member's parameter list.
    ///
    /// `@injected` is rejected on a parameter that already has a default, on a
    /// variadic, and on `inout`: the generated overload drops the parameter and
    /// supplies the value itself, which none of those forms can express.
    private func collectMarkedMember(parameters: FunctionParameterListSyntax,
                                     kind: MarkedMemberRecord.MemberKind,
                                     effects: ProviderEffects,
                                     memberIsGeneric: Bool,
                                     modifiers: DeclModifierListSyntax?,
                                     typeName: String,
                                     typeKind: MarkedTypeKind,
                                     typeIsGeneric: Bool,
                                     typeAccess: AccessRank,
                                     isolation: MarkedMemberIsolation,
                                     location: AttributeLocation) {
        var collected: [MarkedParameter] = []
        var hasMarked = false
        var hadIssue = false

        for parameter in parameters {
            let isMarked = parameter.attributes.hasAttribute(named: "injected")
            if isMarked {
                hasMarked = true
                if parameter.defaultValue != nil {
                    diagnostics.append(CodegenDiagnostic(
                        severity: .error,
                        message: "@injected parameters cannot declare a default value.",
                        location: location
                    ))
                    hadIssue = true
                }
                if parameter.ellipsis != nil {
                    diagnostics.append(CodegenDiagnostic(
                        severity: .error,
                        message: "@injected cannot be applied to variadic parameters.",
                        location: location
                    ))
                    hadIssue = true
                }
                if parameter.type.trimmedDescription.hasPrefix("inout") {
                    diagnostics.append(CodegenDiagnostic(
                        severity: .error,
                        message: "@injected cannot be applied to 'inout' parameters.",
                        location: location
                    ))
                    hadIssue = true
                }
            }

            // Built through `parameterRecord`, not by hand: the markers and the
            // location live there, and restating the fields would drop whatever
            // is added to `ParameterRecord` next.
            collected.append(MarkedParameter(
                parameter: parameter.parameterRecord(locatedBy: { self.location(for: $0) }),
                isMarked: isMarked,
                defaultText: parameter.defaultValue?.value.trimmedDescription
            ))
        }

        guard hasMarked else {
            return
        }

        if typeIsGeneric || memberIsGeneric {
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: "@injected is not supported on generic types or generic members.",
                location: location
            ))
            hadIssue = true
        }

        let effectiveAccess = min(typeAccess, modifiers?.accessRank ?? .internal)
        if effectiveAccess < .internal {
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: "@injected members must be at least internal: the generated overload lives in a separate generated file and cannot call private or fileprivate members.",
                location: location
            ))
            hadIssue = true
        }

        guard !hadIssue else {
            return
        }

        markedMembers.append(MarkedMemberRecord(
            typeName: typeName,
            typeKind: typeKind,
            kind: kind,
            parameters: collected,
            effects: effects,
            isPublic: effectiveAccess >= .public,
            location: location,
            isolation: isolation
        ))
    }

    /// Converts a syntax node to a file/line/column for diagnostics.
    ///
    /// Leading trivia is skipped so the position lands on the declaration
    /// itself rather than on the doc comment or blank lines above it.
    private func location(for syntax: Syntax) -> AttributeLocation {
        guard let converter else {
            return AttributeLocation(filePath: sourceFile, line: 1, column: 1)
        }

        let position = syntax.positionAfterSkippingLeadingTrivia
        let source = converter.location(for: position)
        return AttributeLocation(
            filePath: sourceFile,
            line: source.line,
            column: source.column
        )
    }

    /// The source inside a computed property's braces, with the braces removed.
    ///
    /// Re-emitted verbatim into the generated member, which is what makes an
    /// `@Injectable` value recompute on each resolution rather than being
    /// captured once.
    private func accessorBodyText(from accessorBlock: AccessorBlockSyntax?) -> String? {
        guard let accessorBlock else {
            return nil
        }

        let text = accessorBlock.trimmedDescription
        guard text.first == "{", text.last == "}" else {
            return text
        }

        return String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
