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
    /// Modules `#ZerkImport` asked the generated file to import, from anywhere
    /// in the module. Emitted deduplicated and sorted.
    private(set) var importedModules: Set<String> = []
    /// `@ImportedInjectable` declarations: keys from other modules this one may
    /// resolve against.
    private(set) var importedInjectables: [ImportedInjectableRecord] = []
    /// `@ImportedInjectableValue` declarations: values from other modules this
    /// one may resolve parameters from. Kept apart from `importedInjectables`
    /// because they are matched by name as well as key.
    private(set) var importedValues: [ImportedInjectableValueRecord] = []
    /// Protocol name -> how many primary associated types it declares. See
    /// `visit(_: ProtocolDeclSyntax)`.
    private(set) var protocolPrimaryAssociatedTypeCounts: [String: Int] = [:]

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
        enter(node, typeKind: .classKind, genericParameters: node.declaredGenericParameterNames)
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        _ = typeStack.popLast()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        enter(node, typeKind: .structKind, genericParameters: node.declaredGenericParameterNames)
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        _ = typeStack.popLast()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        enter(node, typeKind: .actorKind, genericParameters: node.declaredGenericParameterNames)
        return .visitChildren
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        _ = typeStack.popLast()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        enter(node, typeKind: .enumKind, genericParameters: node.declaredGenericParameterNames)
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        _ = typeStack.popLast()
    }

    /// `@Injectable` on an `extension` is refused. Children are still visited,
    /// since an `@InjectableValue` inside an extension is collected as usual.
    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.attributes.hasAttribute(named: "Injectable") {
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: InjectableRefusal.extensionTarget(
                    extending: node.extendedType.trimmedDescription),
                location: location(for: Syntax(node))
            ))
        }
        return .visitChildren
    }

    /// Resolves the declaration's isolation once, hands it to the collectors,
    /// then pushes it so members and nested declarations inherit it.
    ///
    /// `genericParameters` is passed down as well as pushed, because the frame
    /// goes on the stack *after* the collectors run — the type's own isolation
    /// is resolved against whatever encloses it, so the push cannot come first —
    /// and the collectors need the type's own parameters in scope.
    private func enter(_ node: some DeclGroupSyntax,
                       typeKind: MarkedTypeKind,
                       genericParameters: [String]) {
        let isolation = resolveTypeIsolation(node)
        collectType(node, isolation: isolation, genericParameters: genericParameters)
        collectMarkedMembers(node, typeKind: typeKind, typeIsGeneric: !genericParameters.isEmpty)
        reportInertAutoInjected(node)

        let sweep = node.attributes.firstAttribute(named: "InjectableValues")
        if sweep?.publicArgument == .nonLiteral {
            diagnostics.append(
                nonLiteralPublicDiagnostic(named: "@InjectableValues", at: location(for: Syntax(node))))
        }

        typeStack.append(
            TypeContext(
                name: node.declaredName,
                isolation: isolation,
                sweptValueMethod: sweep.map { statedValueMethod($0) ?? settings.valueInjectionMethod },
                sweptValuesArePublic: sweep?.publicArgument.isTrue ?? false,
                genericParameterNames: genericParameters
            )
        )
    }

    /// Every generic parameter in scope at the current point of the walk.
    ///
    /// The union of the whole stack rather than its top, because Swift scopes
    /// them that way: `E` remains in scope inside a type nested in
    /// `struct Cache<E>`, so a member there can name it and Zerk has to know.
    private var genericScope: Set<String> {
        typeStack.reduce(into: Set<String>()) { $0.formUnion($1.genericParameterNames) }
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
            /// A parametric `@InjectableValue` resolves its own parameters
            /// whatever encloses it: the type is a namespace, not the thing
            /// being built, so it need not be `@Injectable` for the mark to
            /// mean something.
            var resolvesItsOwnParameters = false

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
                resolvesItsOwnParameters = function.attributes.hasAttribute(named: "InjectableValue")
                    && function.signature.returnClause != nil
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
            guard !resolvesItsOwnParameters else {
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
        collectImport(macroName: node.macroName.text, arguments: node.arguments)
        return .skipChildren
    }

    override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
        collectAlias(macroName: node.macroName.text,
                     arguments: node.genericArgumentClause,
                     syntax: Syntax(node))
        collectImport(macroName: node.macroName.text, arguments: node.arguments)
        return .skipChildren
    }

    /// `#ZerkImport(module: "Foundation")` — names a module the generated file
    /// must import. The macro has already refused anything unreadable, so a
    /// non-literal argument is simply absent here.
    private func collectImport(macroName: String, arguments: LabeledExprListSyntax) {
        guard macroName == "ZerkImport" else {
            return
        }
        for argument in arguments {
            if let module = argument.moduleNameLiteral {
                importedModules.insert(module)
            }
        }
    }

    private func collectAlias(macroName: String,
                              arguments: GenericArgumentClauseSyntax?,
                              syntax: Syntax) {
        guard macroName == "ZerkAlias" else {
            return
        }
        // A generic argument may be a value rather than a type (SE-0453); only
        // types can be alias keys.
        let keys = (arguments?.arguments ?? []).compactMap { argument -> String? in
            guard case .type(let type) = argument.argument else {
                return nil
            }
            return type.normalizedTypeKey
        }
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

    /// `@ImportedInjectable func session(…) -> Session` — a key from another
    /// module, described well enough to resolve against.
    ///
    /// Nothing calls the declaration, so where it sits and how visible it is do
    /// not matter: only the return type, parameters, effects, isolation, and the
    /// expression to resolve through. Visiting every function rather than only a
    /// type's members is deliberate — these are as likely to be global.
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        collectInjectableFunction(node)
        collectParametricValue(node)

        guard node.attributes.hasAttribute(named: "ImportedInjectable"),
              let returnType = node.signature.returnClause?.type else {
            return .skipChildren
        }

        let location = self.location(for: Syntax(node))
        let typeName = returnType.trimmedDescription
        let stated = statedIsolation(modifiers: node.modifiers, attributes: node.attributes)
        validateStatedIsolation(
            stated,
            modifiers: node.modifiers,
            attributes: node.attributes,
            location: location
        )

        importedInjectables.append(
            ImportedInjectableRecord(
                typeKey: returnType.normalizedTypeKey,
                typeName: typeName,
                parameters: node.signature.parameterClause.parameters
                    .parameterRecords(locatedBy: { self.location(for: $0) }),
                effects: ProviderEffects(from: node.signature.effectSpecifiers?.trimmedDescription),
                isolation: stated.resolved(default: ambientIsolation),
                // A written body named the member to resolve through; without
                // one it is the key's own primary. The macro has already refused
                // a body that is not a single Zerk expression.
                callee: node.importedResolutionCallee ?? "Zerk<\(typeName)>.inject",
                resolvesAsProperty: node.importedResolutionIsProperty,
                location: location
            )
        )
        return .skipChildren
    }

    /// Protocols are recorded for their access level and their primary
    /// associated types. A protocol is an injection *key*, never a provider, so
    /// its members are skipped.
    ///
    /// The primary count is only consulted by
    /// `@Injectable<any P>(parameterized: true)`, to check that the key can carry
    /// as many parameters as the type has. A protocol from another module is
    /// absent here and the check is skipped — the compiler still catches it, at
    /// the generated line rather than the declaration.
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        moduleAccessLevels[node.name.text] = node.modifiers.isPublic
        protocolPrimaryAssociatedTypeCounts[node.name.text] =
            node.primaryAssociatedTypeClause?.primaryAssociatedTypes.count ?? 0
        return .skipChildren
    }

    /// A property may be an `@InjectableValue`, an `@Injected` use, or a
    /// misuse of the `@injected` parameter marker. Children are skipped —
    /// nothing nested inside a property declaration can be any of those.
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        collectImportedValue(node)
        collectInjectableProperty(node)
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
    /// A type can be injectable under several keys at once, and both
    /// `@Injectable(primary:)` and `@Injectable(public:)` apply per key rather
    /// than per type, so all three are gathered as dictionaries keyed by type
    /// key.
    private func collectType(_ node: some DeclGroupSyntax,
                             isolation typeIsolation: ProviderIsolation,
                             genericParameters: [String]) {
        moduleAccessLevels[node.declaredName] = node.modifiers.isPublic

        let injectableAttributes = node.attributes.attributes(named: "Injectable")
        guard !injectableAttributes.isEmpty else { return }

        let isSingleton = node.attributes.hasAttribute(named: "Singleton")
        let location = self.location(for: Syntax(node))
        // The type's own parameters are not on `typeStack` yet — `enter` pushes
        // the frame only after this returns — so they are unioned in by hand.
        let scope = genericScope.union(genericParameters)

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
            if attribute.publicArgument == .nonLiteral {
                diagnostics.append(nonLiteralPublicDiagnostic(named: "@Injectable", at: location))
            }
        }

        if isSingleton && (node.is(StructDeclSyntax.self) || node.is(EnumDeclSyntax.self)) {
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: "@Singleton can only be applied to reference types (class or actor).",
                location: location
            ))
        }

        // A generic type is recorded in full — parameters, providers, and which
        // parameters each provider mentions — and refused later, by
        // ``GenericGate``, which is the one place that knows what the emitter
        // can spell. Reading it here and refusing there keeps this layer honest
        // about what the source says, and makes the refusal a single seam to
        // remove rather than a hole in the collector.

        // A generic type's own key is its ``KeyShape`` — `Cache<#0>` — not the
        // bare `Cache`, which is not a type, and not `Cache<E>`, which would
        // file one family under as many keys as there are ways to spell the
        // parameter. The display name keeps the spelling the emitter wants.
        let ownKey = KeyShape.text(base: node.declaredName, arity: genericParameters.count)
        let ownDisplayKey = genericParameters.isEmpty
            ? node.declaredName
            : "\(node.declaredName)<\(genericParameters.joined(separator: ", "))>"

        var injectableKeys: [String: AttributeLocation] = [:]
        var parameterizedKeys: [String: AttributeLocation] = [:]
        for attribute in injectableAttributes {
            // `parameterized: true` rewrites the written key: the type's own
            // parameters become the protocol's primary associated types, so
            // `@Injectable<any P>` on `Box<X, Y>` keys on `any P<X, Y>`. That is
            // a *pattern*, exactly like the type's own key, so it files under a
            // shape and emits through the same generic path.
            switch parameterizedKey(for: attribute,
                                    typeName: node.declaredName,
                                    genericParameters: genericParameters,
                                    at: location) {
            case .key(let key, let display):
                injectableKeys[key] = location
                parameterizedKeys[key] = location
                recordKeyDisplayName(display, for: key)
                continue
            case .invalid:
                // Already reported. Falling through to the plain key path would
                // report a second, unrelated error about the same attribute.
                continue
            case .notRequested:
                break
            }

            let genericKeys = attribute.genericArgumentKeys
            let keys = genericKeys.isEmpty ? [ownKey] : genericKeys
            // Paired with `keys` by index: the same types, canonicalized with
            // `any` kept. An unparameterized @Injectable keys on the type
            // itself, which is a bare identifier unless the type is generic.
            let displayKeys = genericKeys.isEmpty
                ? [ownDisplayKey]
                : attribute.genericArgumentDisplayKeys

            for (offset, key) in keys.enumerated() {
                injectableKeys[key] = location
                recordKeyDisplayName(displayKeys[offset], for: key)
            }
        }

        // `public:` rides on the attribute that names the key, exactly as
        // `primary:` does, so `@Injectable<A>(public: true) @Injectable<B>`
        // exports A and leaves B internal.
        var exportedKeys: [String: AttributeLocation] = [:]
        for attribute in injectableAttributes where attribute.publicArgument.isTrue {
            let genericKeys = attribute.genericArgumentKeys
            let keys = genericKeys.isEmpty ? [ownKey] : genericKeys
            for key in keys {
                exportedKeys[key] = location
            }
        }

        // `@Injectable<A>(primary: true) @Injectable<B>` claims A only: primacy
        // rides on the attribute that names the key, not on the declaration.
        var primaryKeys: [String: AttributeLocation] = [:]
        for attribute in injectableAttributes where attribute.primaryArgument.isTrue {
            let genericKeys = attribute.genericArgumentKeys
            let keys = genericKeys.isEmpty ? [ownKey] : genericKeys
            for key in keys {
                primaryKeys[key] = location
            }
        }

        var defaultProviders: [InjectingProvider] = []
        var typedProviders: [String: [InjectingProvider]] = [:]
        var initializers: [InitializerRecord] = []

        for member in node.memberBlock.members {
            if let initializer = member.decl.as(InitializerDeclSyntax.self) {
                // A provider may add generic parameters of its own —
                // `init<Z>(x: X, y: Y, z: Z)` inside `Box<X, Y>` — and inside
                // its signature those are in scope alongside the type's. Read
                // with the type's scope alone, `z: Z` would look like a
                // dependency on a module type named `Z`.
                let initializerGenerics = initializer.genericParameterClause?
                    .parameters.map { $0.name.text } ?? []
                let parameters = initializer.signature.parameterClause.parameters
                    .parameterRecords(locatedBy: { self.location(for: $0) },
                                      genericScope: scope.union(initializerGenerics))
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
                        isolation: initializerIsolation,
                        genericParameters: initializerGenerics
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
                    // `produced: nil` refuses `typeNamed:`: an initializer only
                    // ever builds its own type, which its member is named after
                    // already. A naming mistake keeps the provider — the error
                    // is reported, and dropping it would add "no provider for
                    // key" on top of it.
                    let memberName = statedMemberName(
                        from: [attribute],
                        attribute: "@InjectableProviding",
                        declared: nil,
                        produced: nil,
                        typeNamedRefusal: MemberNamingRefusal.typeNamedOnInitializer,
                        at: initializerLocation
                    ) ?? .typeName
                    defaultProviders.append(
                        InjectingProvider(
                            kind: .initializer,
                            parameters: parameters,
                            effects: effects,
                            location: initializerLocation,
                            returnTypeName: nil,
                            isolation: initializerIsolation,
                            isPrimary: attribute.primaryArgument.isTrue,
                            genericParameters: initializerGenerics,
                            memberName: memberName
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

            // A factory may declare generic parameters of its own, exactly as an
            // initializer may. Whether each one can actually be inferred is a
            // question about the whole signature, so `ProviderResolver` asks it
            // once for every provider rather than each collection site guessing.
            let functionGenerics = function.genericParameterClause?
                .parameters.map { $0.name.text } ?? []

            let returnType = function.signature.returnClause?.type.trimmedDescription ?? ""
            // What `typeNamed:` names the member after: the type the factory
            // *returns*, not the type it is declared inside. The two differ
            // exactly when the factory is worth renaming — a provider type
            // exists to build something that is not itself.
            let producedName = function.signature.returnClause?.type.nominalBaseName
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

                // Named per attribute, as `primary` is: a factory bound to two
                // keys can be called something different under each.
                let memberName = statedMemberName(
                    from: [attribute],
                    attribute: "@InjectableProviding",
                    declared: function.name.text,
                    produced: producedName,
                    typeNamedRefusal: MemberNamingRefusal.typeNamedNeedsNamedType(
                        attribute: "@InjectableProviding",
                        type: returnType
                    ),
                    at: functionLocation
                ) ?? .stated(function.name.text)

                let provider = InjectingProvider(
                    kind: .staticFunction(name: function.name.text),
                    parameters: function.signature.parameterClause.parameters
                        .parameterRecords(locatedBy: { self.location(for: $0) },
                                          genericScope: scope.union(functionGenerics)),
                    effects: ProviderEffects(from: function.signature.effectSpecifiers?.trimmedDescription),
                    location: functionLocation,
                    returnTypeName: returnType.isEmpty ? nil : returnType,
                    isolation: functionStated.resolved(default: typeIsolation),
                    isPrimary: attribute.primaryArgument.isTrue,
                    genericParameters: functionGenerics,
                    memberName: memberName
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

        if initializers.isEmpty,
           var inferredInitializer = node.inferredSynthesizedInitializer(in: location,
                                                                        genericScope: scope) {
            inferredInitializer.isolation = typeIsolation
            initializers.append(inferredInitializer)
        }

        types.append(
            TypeRecord(
                name: node.declaredName,
                injectableKeys: injectableKeys,
                exportedKeys: exportedKeys,
                primaryKeys: primaryKeys,
                defaultProviders: defaultProviders,
                typedProviders: typedProviders,
                initializers: initializers,
                isSingleton: isSingleton,
                isolation: typeIsolation,
                genericParameters: genericParameters,
                parameterizedKeys: parameterizedKeys
            )
        )
    }

    /// What `parameterized:` asked for, if anything.
    ///
    /// `invalid` is distinct from `notRequested` on purpose: the attribute did
    /// ask, and was already reported, so the caller must not fall through to the
    /// plain key path and report a second error about the same attribute.
    enum ParameterizedKey {
        case notRequested
        case invalid
        case key(String, display: String)
    }

    /// The key `@Injectable<any P>(parameterized: true)` asks for.
    ///
    /// Returns both spellings the rest of the pipeline needs: the *shape* it is
    /// filed and matched under (`P<#0, #1>`), and the spelling emitted into the
    /// generated file (`any P<X, Y>`, in the type's own parameter names).
    ///
    /// Every way of getting this wrong is a compile error in Swift with a good
    /// message — "does not have primary associated types that can be
    /// constrained", "specialized with too many type arguments" — but at the
    /// *generated* line, which is the thing worth avoiding.
    private func parameterizedKey(for attribute: AttributeSyntax,
                                  typeName: String,
                                  genericParameters: [String],
                                  at location: AttributeLocation) -> ParameterizedKey {
        guard attribute.parameterizedArgument != .absent else {
            return .notRequested
        }
        if attribute.parameterizedArgument == .nonLiteral {
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: "@Injectable(parameterized:) requires a 'true' or 'false' literal. Zerk reads this from source and cannot evaluate an expression.",
                location: location
            ))
            return .invalid
        }
        guard attribute.parameterizedArgument.isTrue else {
            return .notRequested
        }

        guard !genericParameters.isEmpty else {
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: GenericRefusal.parameterizedNonGeneric(type: typeName),
                location: location
            ))
            return .invalid
        }

        let written = attribute.genericArgumentDisplayKeys.first
        guard let written, written.hasPrefix("any ") else {
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: GenericRefusal.parameterizedNeedsExistentialKey(type: typeName, key: written),
                location: location
            ))
            return .invalid
        }

        let base = attribute.genericArgumentKeys[0]
        if let primaryCount = protocolPrimaryAssociatedTypeCounts[base],
           primaryCount != genericParameters.count {
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: GenericRefusal.parameterizedArityMismatch(
                    type: typeName,
                    key: written,
                    parameters: genericParameters,
                    primaryCount: primaryCount
                ),
                location: location
            ))
            return .invalid
        }

        return .key(
            KeyShape.text(base: base, arity: genericParameters.count),
            display: "\(written)<\(genericParameters.joined(separator: ", "))>"
        )
    }

    /// `@InjectableValue static func greeting(name: String) -> String` — a value
    /// computed from parameters.
    ///
    /// The return type is the key and the declaration's name is what a parameter
    /// must be called to match it, exactly as for the property form. What is
    /// different is the parameters: they behave as an `@InjectableProviding`
    /// provider's do, so they are collected the same way, markers included, and
    /// classified by the same machinery.
    private func collectParametricValue(_ node: FunctionDeclSyntax) {
        let attributes = node.attributes.attributes(named: "InjectableValue")
        guard let returnType = node.signature.returnClause?.type else {
            return
        }
        // Annotated, or swept up by an enclosing `@InjectableValues`. A swept
        // member that cannot be injected is skipped rather than reported: the
        // marker is a statement about the type, not a promise about every
        // member — the same rule the property sweep follows.
        if attributes.isEmpty {
            guard typeStack.last?.sweptValueMethod != nil,
                  !node.attributes.hasAttribute(named: "NonInjectable"),
                  node.modifiers.isStatic,
                  node.modifiers.accessRank > .fileprivate,
                  node.genericParameterClause == nil,
                  node.body != nil,
                  returnType.normalizedTypeKey != "Void" else {
                return
            }
        }

        let location = self.location(for: Syntax(node))

        // A swept member is already filtered out above, silently, because the
        // sweep is a statement about the type rather than a promise about every
        // member. An annotation is a promise, so this one is reported.
        if node.genericParameterClause != nil {
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: GenericRefusal.injectableValueFunction,
                location: location
            ))
            return
        }

        for attribute in attributes where attribute.publicArgument == .nonLiteral {
            diagnostics.append(nonLiteralPublicDiagnostic(named: "@InjectableValue", at: location))
        }

        let stated = statedIsolation(modifiers: node.modifiers, attributes: node.attributes)
        validateStatedIsolation(
            stated,
            modifiers: node.modifiers,
            attributes: node.attributes,
            location: location
        )

        let genericKeys = attributes.flatMap(\.genericArgumentKeys)
        let keys = genericKeys.isEmpty ? [returnType.normalizedTypeKey] : genericKeys
        let displayKeys = genericKeys.isEmpty
            ? [returnType.displayTypeKey]
            : attributes.flatMap(\.genericArgumentDisplayKeys)

        let isExported = attributes
            .map(\.publicArgument)
            .first { $0 != .absent }
            .map(\.isTrue)
            ?? (typeStack.last?.sweptValuesArePublic ?? false)

        for (offset, key) in keys.enumerated() {
            recordKeyDisplayName(displayKeys[offset], for: key)
            values.append(
                InjectableValueRecord(
                    name: node.name.text,
                    typeKey: key,
                    typeName: returnType.trimmedDescription,
                    keyDisplayName: displayKeys[offset],
                    // The generated member calls the declaration rather than
                    // reproducing its body, so there is nothing to copy.
                    bodyText: nil,
                    location: location,
                    isolation: stated.resolved(default: ambientIsolation),
                    injectionMethod: .referenced,
                    enclosingTypePath: enclosingTypePath,
                    parameters: node.signature.parameterClause.parameters
                        .parameterRecords(locatedBy: { self.location(for: $0) }),
                    effects: ProviderEffects(from: node.signature.effectSpecifiers?.trimmedDescription),
                    isExported: isExported
                )
            )
        }
    }

    /// `@ImportedInjectableValue var apiKey: String { Zerk<String>.apiKey }` — a
    /// value from another module, matched here by key *and* name.
    ///
    /// Nothing calls the declaration, so where it sits and how visible it is do
    /// not matter: only the annotation (the key), the declaration's own name
    /// (what parameters must be called), and the expression to read through.
    /// The macro has already refused every shape this cannot read, so anything
    /// incomplete is simply skipped rather than reported twice.
    private func collectImportedValue(_ node: VariableDeclSyntax) {
        guard node.attributes.hasAttribute(named: "ImportedInjectableValue"),
              let binding = node.bindings.first,
              node.bindings.count == 1,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
              let annotation = binding.typeAnnotation,
              let expression = binding.importedValueExpression else {
            return
        }

        let location = self.location(for: Syntax(node))
        let stated = statedIsolation(modifiers: node.modifiers, attributes: node.attributes)
        validateStatedIsolation(
            stated,
            modifiers: node.modifiers,
            attributes: node.attributes,
            location: location
        )

        importedValues.append(
            ImportedInjectableValueRecord(
                typeKey: annotation.type.normalizedTypeKey,
                typeName: annotation.type.trimmedDescription,
                name: identifier.identifier.text,
                expression: expression,
                isolation: stated.resolved(default: ambientIsolation),
                location: location
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

    /// `public:` is read from source rather than evaluated, for the same reason
    /// `primary:` is — so an unreadable expression has to be reported instead of
    /// quietly resolving to "not exported".
    private func nonLiteralPublicDiagnostic(named attributeName: String,
                                            at location: AttributeLocation) -> CodegenDiagnostic {
        CodegenDiagnostic(
            severity: .error,
            message: "\(attributeName)(public:) requires a 'true' or 'false' literal. Zerk reads this from source and cannot evaluate an expression.",
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
        let injectableAttributes = node.attributes.attributes(named: "InjectableValue")
        let sweptMethod = typeStack.last?.sweptValueMethod
        let sweptIsExported = typeStack.last?.sweptValuesArePublic ?? false

        guard !injectableAttributes.isEmpty else {
            if let sweptMethod {
                collectSweptValue(node, method: sweptMethod, isExported: sweptIsExported)
            }
            return
        }

        guard let binding = node.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
              let annotation = binding.typeAnnotation else {
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: "@InjectableValue must declare a single named binding with an explicit type.",
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
        let bodyText = binding.valueBodyText
        let effects = ProviderEffects(from: binding.getterEffectSpecifiers)
        let valueLocation = location(for: Syntax(node))

        for attribute in injectableAttributes where attribute.primaryArgument != .absent {
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: "'primary' applies to types only. A value is the sole provider for its key, so there is nothing to be primary over.",
                location: valueLocation
            ))
        }

        for attribute in injectableAttributes where attribute.publicArgument == .nonLiteral {
            diagnostics.append(nonLiteralPublicDiagnostic(named: "@InjectableValue", at: valueLocation))
        }

        let method = injectableAttributes.compactMap(statedValueMethod).first
            ?? sweptMethod
            ?? settings.valueInjectionMethod

        // Written on the declaration, `public:` answers for it — including
        // `public: false` against an enclosing `@InjectableValues(public: true)`.
        // Saying nothing is what defers to the sweep.
        let isExported = injectableAttributes
            .map(\.publicArgument)
            .first { $0 != .absent }
            .map(\.isTrue)
            ?? sweptIsExported

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
                    effects: effects,
                    isSettable: isSettable(node, binding: binding),
                    isExported: isExported
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
    private func collectSweptValue(_ node: VariableDeclSyntax,
                                   method: ValueInjectionMethod,
                                   isExported: Bool) {
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
                bodyText: binding.valueBodyText,
                location: valueLocation,
                isolation: stated.resolved(default: ambientIsolation),
                injectionMethod: method,
                enclosingTypePath: enclosingTypePath,
                effects: ProviderEffects(from: binding.getterEffectSpecifiers),
                isSettable: isSettable(node, binding: binding),
                isExported: isExported
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
            var injectedType = annotation.type
            if let unwrapped = annotation.type.unwrappedOptional {
                typeKey = unwrapped.normalizedTypeKey
                injectedType = unwrapped
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
                    // Read from whichever type supplied the key, so the shape
                    // and the key can never describe different types.
                    typeKeyShape: attribute.genericArgumentTypes.first?.typeKeyShape
                        ?? injectedType.typeKeyShape,
                    macroName: "@\(macroName)",
                    namesMemberDirectly: namesMemberDirectly,
                    location: location(for: Syntax(node))
                ))
            }
        }
    }


    // MARK: - @Injectable declarations
    //
    // A global or static var/func carrying `@Injectable` registers the type it
    // *produces*, with itself as the provider. This is how a type Zerk cannot
    // annotate — one from another module — joins the graph as a real key rather
    // than as a value matched by name.

    /// Records `@Injectable` on a variable, if it carries one.
    private func collectInjectableProperty(_ node: VariableDeclSyntax) {
        let attributes = node.attributes.attributes(named: "Injectable")
        guard !attributes.isEmpty else {
            return
        }
        guard let binding = node.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
              let annotation = binding.typeAnnotation else {
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: "@Injectable on a property needs a single named binding with an explicit type — the type is the key.",
                location: location(for: Syntax(node))
            ))
            return
        }
        collectInjectableDeclaration(
            node: Syntax(node),
            attributes: attributes,
            declaredName: identifier.identifier.text,
            producedType: annotation.type,
            genericParameters: [],
            parameters: [],
            effects: ProviderEffects(from: binding.getterEffectSpecifiers),
            modifiers: node.modifiers,
            isProperty: true
        )
    }

    /// Records `@Injectable` on a function, if it carries one.
    private func collectInjectableFunction(_ node: FunctionDeclSyntax) {
        let attributes = node.attributes.attributes(named: "Injectable")
        guard !attributes.isEmpty else {
            return
        }
        guard let returnType = node.signature.returnClause?.type,
              returnType.normalizedTypeKey != "Void" else {
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: "@Injectable on a function needs a return type — it is the key.",
                location: location(for: Syntax(node))
            ))
            return
        }
        let ownGenerics = node.genericParameterClause?.parameters.map { $0.name.text } ?? []
        collectInjectableDeclaration(
            node: Syntax(node),
            attributes: attributes,
            declaredName: node.name.text,
            producedType: returnType,
            genericParameters: ownGenerics,
            parameters: node.signature.parameterClause.parameters
                .parameterRecords(locatedBy: { self.location(for: $0) },
                                  genericScope: genericScope.union(ownGenerics)),
            effects: ProviderEffects(from: node.signature.effectSpecifiers?.trimmedDescription),
            modifiers: node.modifiers,
            isProperty: false
        )
    }

    /// The shared body: one `TypeRecord` whose single provider is the
    /// declaration itself.
    ///
    /// A `TypeRecord` rather than a new kind of record, because everything
    /// downstream — election, classification, emission — already works in those
    /// terms. `name` is the *produced type*, not the declaration, which is also
    /// what `typeNamed:` names the member after.
    private func collectInjectableDeclaration(node: Syntax,
                                              attributes: [AttributeSyntax],
                                              declaredName: String,
                                              producedType: TypeSyntax,
                                              genericParameters: [String],
                                              parameters: [ParameterRecord],
                                              effects: ProviderEffects,
                                              modifiers: DeclModifierListSyntax,
                                              isProperty: Bool) {
        let location = self.location(for: node)

        // Global, or a type's static member. An instance member has no stable
        // reference the generated file could call, and a local one is not
        // visible to it at all.
        guard typeStack.isEmpty || modifiers.isStatic else {
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: "@Injectable on a member needs it to be 'static': the generated file calls '\(typeStack.map(\.name).joined(separator: "."))\(typeStack.isEmpty ? "" : ".")\(declaredName)' directly, and an instance member has no such reference.",
                location: location
            ))
            return
        }
        guard modifiers.accessRank > .fileprivate else {
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: "@Injectable on '\(declaredName)' requires it to be at least internal: the generated file is a separate file in this module and cannot reach a private declaration.",
                location: location
            ))
            return
        }

        // A generic declaration registers exactly as `struct Box<X, Y>` does —
        // under the shape `Box<#0, #1>`, displayed as written. A concrete one
        // keys on the produced type itself.
        let baseName = producedType.nominalBaseName ?? producedType.trimmedDescription

        guard let memberName = statedMemberName(
            from: attributes,
            attribute: "@Injectable",
            declared: declaredName,
            produced: producedType.nominalBaseName,
            typeNamedRefusal: MemberNamingRefusal.typeNamedNeedsNamedType(
                attribute: "@Injectable",
                type: producedType.trimmedDescription
            ),
            at: location
        ) else {
            return
        }
        let ownKey = genericParameters.isEmpty
            ? producedType.normalizedTypeKey
            : KeyShape.text(base: baseName, arity: genericParameters.count)
        let ownDisplayKey = genericParameters.isEmpty
            ? producedType.displayTypeKey
            : producedType.trimmedDescription

        var injectableKeys: [String: AttributeLocation] = [:]
        var exportedKeys: [String: AttributeLocation] = [:]
        var primaryKeys: [String: AttributeLocation] = [:]
        for attribute in attributes {
            if attribute.publicArgument == .nonLiteral {
                diagnostics.append(nonLiteralPublicDiagnostic(named: "@Injectable", at: location))
            }
            if attribute.primaryArgument == .nonLiteral {
                diagnostics.append(nonLiteralPrimaryDiagnostic(at: location))
            }
            let written = attribute.genericArgumentKeys
            let keys = written.isEmpty ? [ownKey] : written
            let displays = written.isEmpty ? [ownDisplayKey] : attribute.genericArgumentDisplayKeys
            for (offset, key) in keys.enumerated() {
                injectableKeys[key] = location
                recordKeyDisplayName(displays[offset], for: key)
                if attribute.publicArgument.isTrue { exportedKeys[key] = location }
                if attribute.primaryArgument.isTrue { primaryKeys[key] = location }
            }
        }

        // A static member is reached by its qualified path. A global is not
        // reachable at all from inside the extension — the member being defined
        // shadows it — so it goes through a thunk declared at file scope.
        let path = typeStack.map(\.name)
        let reference = (path + [declaredName]).joined(separator: ".")
        let thunk = path.isEmpty
            ? "_$zerk_provider_\(declaredName)"
            : nil
        let provider = InjectingProvider(
            kind: .declaration(reference: reference, isProperty: isProperty, thunk: thunk),
            parameters: parameters,
            effects: effects,
            location: location,
            returnTypeName: producedType.trimmedDescription,
            isolation: statedIsolation(modifiers: modifiers, attributes: AttributeListSyntax([]))
                .resolved(default: ambientIsolation),
            isPrimary: false,
            genericParameters: [],
            memberName: memberName
        )

        types.append(
            TypeRecord(
                name: baseName,
                injectableKeys: injectableKeys,
                exportedKeys: exportedKeys,
                primaryKeys: primaryKeys,
                defaultProviders: [provider],
                typedProviders: [:],
                initializers: [],
                isSingleton: false,
                isolation: provider.isolation,
                genericParameters: genericParameters
            )
        )
    }

    // MARK: - Member naming

    /// What the member generated for a provider is called.
    ///
    /// Three answers, and the attribute picks between them: the declaration's
    /// own name by default, the type it produces under `typeNamed:`, or whatever
    /// `name:` says.
    ///
    /// - Parameters:
    ///   - declared: what the member is called with nothing stated — a
    ///     declaration's or a factory's own name, and `nil` for an initializer,
    ///     which has none.
    ///   - produced: the name of the type the provider builds, which is what
    ///     `typeNamed:` names the member after. `nil` when there is no such name
    ///     to take, which `typeNamedRefusal` explains.
    ///   - typeNamedRefusal: what to report if `typeNamed:` is asked for anyway.
    ///     The reasons differ — an initializer produces its own type and is
    ///     named after it already, while a factory may return something
    ///     unnamed — so the caller, which knows which it has, supplies it.
    ///
    /// Returns `nil` when the attributes disagree, having reported it.
    private func statedMemberName(from attributes: [AttributeSyntax],
                                  attribute name: String,
                                  declared: String?,
                                  produced: String?,
                                  typeNamedRefusal: String,
                                  at location: AttributeLocation) -> ProviderMemberName? {
        var typeNamed = false
        var explicit: String?

        for attribute in attributes {
            switch attribute.typeNamedArgument {
            case .nonLiteral:
                diagnostics.append(CodegenDiagnostic(
                    severity: .error,
                    message: MemberNamingRefusal.nonLiteralTypeNamed(attribute: name),
                    location: location
                ))
                return nil
            case .literal(let value):
                guard produced != nil else {
                    diagnostics.append(CodegenDiagnostic(
                        severity: .error,
                        message: typeNamedRefusal,
                        location: location
                    ))
                    return nil
                }
                typeNamed = typeNamed || value
            case .absent:
                break
            }

            switch attribute.nameArgument {
            case .nonLiteral:
                diagnostics.append(CodegenDiagnostic(
                    severity: .error,
                    message: MemberNamingRefusal.nonLiteralName(attribute: name),
                    location: location
                ))
                return nil
            case .literal(let value):
                explicit = value
            case .absent:
                break
            }
        }

        if typeNamed, let explicit {
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: MemberNamingRefusal.conflictingNames(attribute: name, name: explicit),
                location: location
            ))
            return nil
        }
        if typeNamed, let produced {
            return .stated(produced.memberNameForType)
        }
        if let stated = explicit ?? declared {
            return .stated(stated)
        }
        return .typeName
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
}
