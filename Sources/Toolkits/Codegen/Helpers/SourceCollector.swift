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
    /// Every type and protocol declared in the module -> the access it was
    /// written with, keyed by **qualified** name.
    ///
    /// One map rather than two. It used to sit beside a `[String: Bool]` saying
    /// only whether each was public, and the pair recorded the same fact twice —
    /// `isPublic` is `>= .public` — filled at different sites with different
    /// keys. That split is what let the same unqualified-name mistake be made in
    /// both: an injectable key for a nested type is `Outer.Inner`, so a map keyed
    /// by `Inner` never matches and every check reading it is silently skipped.
    private(set) var declaredAccessRanks: [String: [DeclaredAccessRecord]] = [:]
    /// Every type declared in the module -> its generic parameters, keyed by
    /// **qualified** name as ``declaredAccessRanks`` is.
    ///
    /// Recorded for every type, not just injectable ones, because the question
    /// it answers is asked about a type Zerk may never register: whether
    /// `extension Cache` puts generic parameters in scope. An extension names no
    /// parameters of its own, and the type it extends may be walked after it, so
    /// this cannot be settled while collecting — see
    /// ``MarkedMemberRecord/unboundExtendedTypeName``.
    private(set) var declaredGenericParameters: [String: [String]] = [:]
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
    /// Injectable key -> every nominal type its spelling mentions.
    ///
    /// Collected from the syntax tree at the moment the key is recorded, because
    /// the canonical key cannot be taken apart afterwards — see
    /// ``TypeSyntax/nominalNames``. Read when deciding whether the generated
    /// members may be `public`.
    private(set) var keyNominalNames: [String: Set<String>] = [:]
    /// `@InjectableAlias` / `#InjectableAlias` declarations, which merge keys before
    /// resolution. See ``KeyAliases``.
    private(set) var aliasDeclarations: [AliasDeclaration] = []
    /// File -> every nominal type name that file put into something Zerk emits.
    ///
    /// Read together with ``filesWithDeclarations`` to decide whose imports the
    /// generated file needs. A file whose names are all declared in this module
    /// contributed nothing the generated file cannot already see, so its imports
    /// are not copied.
    ///
    /// Accounted for at three places, and the list is the whole of it: every key
    /// (through ``recordKey(display:nominalNames:for:)``, which is the only way
    /// to register one), every provider parameter, and every `@injected`
    /// member's own signature. A source of emitted names that did not report
    /// here would cost a needed import, so the narrowing errs the other way —
    /// see ``filesWithDeclarations``.
    private(set) var mentionedNamesByFile: [String: Set<String>] = [:]
    /// File -> the modules it imports, with the guard each sits under.
    private var importsByFile: [String: [(String, CompilationCondition)]] = [:]
    /// Files carrying any declaration Zerk collects.
    ///
    /// A file in here with *no* recorded names is included anyway. That is the
    /// "I did not account for this" case: it means the file registered something
    /// whose names nothing above reported, and dropping its imports on that
    /// basis would reintroduce exactly the failure automatic imports removed.
    private(set) var filesWithDeclarations: Set<String> = []
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
    /// The `#if` clauses enclosing whatever is being visited, outermost first.
    private var conditionStack: [ConditionClause] = []
    /// Extended type names, for the same reason ``typeStack`` exists — an
    /// `extension` is not a declaration Zerk registers, so it pushes no type
    /// frame, but its members are still read.
    private var extensionStack: [String] = []

    /// Where the walk currently is, in `#if` terms.
    private var currentCondition: CompilationCondition {
        CompilationCondition(clauses: conditionStack)
    }

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

    override func visitPost(_ node: ExtensionDeclSyntax) {
        _ = extensionStack.popLast()
    }

    /// `@Injectable` on an `extension` is refused. Children are still visited,
    /// since an `@InjectableValue` inside an extension is collected as usual.
    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        extensionStack.append(node.extendedType.trimmedDescription)
        collectMarkedExtensionMembers(node)
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

    // MARK: - Conditional compilation

    /// Walks each clause of a `#if` with that clause pushed, so every
    /// registration inside records the guard it was written under.
    ///
    /// The default visitor walks the clauses as if they were all present at
    /// once, which is how a `#if DEBUG` / `#else` pair used to read as two
    /// competing registrations of one key. Walking them separately is what makes
    /// them alternatives: same code, one clause each, and
    /// ``CompilationCondition/areExclusive(_:_:)`` can then tell that no build
    /// sees both.
    ///
    /// The clauses are still *all* walked — Zerk resolves every configuration in
    /// one pass, because it has no way to know which one is being built and no
    /// reason to prefer one. A mistake in the branch you are not building today
    /// is reported today.
    override func visit(_ node: IfConfigDeclSyntax) -> SyntaxVisitorContinueKind {
        // Inside a type, a `#if` around an initializer or a provider would give
        // that type two shapes and the generated member only has one. Refused
        // here rather than in the resolver: this is the only place that still
        // knows the `#if` existed.
        // An `extension` pushes no type frame, so it is tracked separately —
        // without this the refusal never fired inside one, and a conditional
        // `@injected` member there was dropped exactly as it used to be inside
        // a type body.
        let enclosing = typeStack.last.map { ($0.name, $0.consultsInference) }
            // An extension cannot declare stored properties, so nothing there
            // can change an inferred initializer.
            ?? extensionStack.last.map { ($0, false) }

        if let enclosing,
           ConditionalCompilation.gatesConstruction(node, consultsInference: enclosing.1) {
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: "'\(enclosing.0)' is read differently per configuration: this #if gates an initializer, an @InjectableProviding provider, a stored property, or a member with @injected parameters. Zerk reads a type's members without expanding conditions, so what is inside would be missed — put the #if around the whole type instead, so each configuration declares its own, or move the condition inside the member's body where it changes no signature.",
                location: location(for: Syntax(node))
            ))
        }

        let branch = branchIdentity(of: node)
        var preceding: [String] = []

        for (index, clause) in node.clauses.enumerated() {
            let condition = clause.condition.map { Self.normalizedCondition($0.trimmedDescription) }
            conditionStack.append(
                ConditionClause(branch: branch,
                                index: index,
                                condition: condition,
                                precedingConditions: preceding)
            )
            if let elements = clause.elements {
                walk(elements)
            }
            conditionStack.removeLast()

            if let condition {
                preceding.append(condition)
            }
        }

        return .skipChildren
    }

    /// A declaration's name qualified by everything it is nested inside.
    ///
    /// Extensions come first and can only be outermost — Swift allows them at
    /// file scope only — so `extension A { struct B { struct C {} } }` gives
    /// `A.B.C`, which is what the key for a nested type looks like and what an
    /// `extension A.B` names.
    private func qualified(_ name: String) -> String {
        (extensionStack + typeStack.map(\.name) + [name]).joined(separator: ".")
    }

    /// Identity of one `#if`, as file and offset.
    ///
    /// Clause exclusivity compares these, so it has to distinguish two `#if`s
    /// with identical conditions — which can both be active — from two clauses
    /// of one `#if`, which cannot.
    private func branchIdentity(of node: IfConfigDeclSyntax) -> String {
        // Zero-padded: the identity is compared as text, and "1000" sorts
        // before "999" unless the widths match.
        "\(sourceFile):\(CompilationCondition.padded(node.positionAfterSkippingLeadingTrivia.utf8Offset))"
    }

    /// Flattens a condition to one line, since it is emitted as one.
    ///
    /// A condition may be written across lines or carry comments between its
    /// operands; both are trivia the guard does not need, and a newline inside
    /// an emitted `#if` would end the directive early.
    private static func normalizedCondition(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
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
                consultsInference: !node.declaresItsOwnProvider,
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

    /// `@InjectableAlias typealias Persisting = Storing` — the alias and the type it
    /// names become one key.
    ///
    /// A generic typealias is rejected by the macro; skipping it here keeps the
    /// plugin from acting on something the macro already refused.
    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.attributes.hasAttribute(named: "InjectableAlias") else {
            return .skipChildren
        }
        guard node.genericParameterClause?.parameters.isEmpty ?? true else {
            return .skipChildren
        }

        let aliasKey = node.name.text
        let initializer = node.initializer.value
        keyNominalNames[aliasKey, default: []].formUnion(initializer.nominalNames)
        keyNominalNames[initializer.normalizedTypeKey, default: []].formUnion(initializer.nominalNames)
        aliasDeclarations.append(
            AliasDeclaration(
                keys: [aliasKey, initializer.normalizedTypeKey],
                aliasKey: aliasKey,
                location: location(for: Syntax(node))
            )
        )
        return .skipChildren
    }

    /// `#InjectableAlias<A, B, C>()` — every listed type is the same key.
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

    /// Every `import` in a file Zerk reads becomes an import of the file Zerk
    /// writes.
    ///
    /// The generated file names types it did not declare — a key written
    /// `@Injectable<URLSession>`, a provider parameter typed `Date`, an
    /// `@injected` member's own signature — and reading syntax cannot tell which
    /// module a name came from. Asking the developer to restate it was what
    /// `#ZerkImport` did, and restating is the part that goes wrong: the failure
    /// is a missing name inside a generated file, and it arrives every time
    /// somebody touches a foreign type.
    ///
    /// Copying the imports instead is correct by construction rather than by
    /// diligence. A declaration mentioning `Date` sits in a file that imports
    /// `Foundation`, or that file would not compile — so the union over the
    /// files Zerk reads can only ever be a *superset* of what the generated file
    /// needs. It cannot under-import, which is the failure `#ZerkImport` had.
    ///
    /// Two things are deliberately not copied:
    ///
    /// - **`@testable`**, which the generated file has no business carrying: it
    ///   belongs to a test target, and reproducing it in one that is not is
    ///   either an error or a lie about what the module can see.
    /// - **Access-level modifiers and other attributes.** A plain `import` is
    ///   what the generated file needs; `internal import X` restates a boundary
    ///   about *that* file, not about this one.
    ///
    /// The `#if` a file's import sits under travels with it, exactly as a
    /// registration's does, so a debug-only module stays debug-only. See
    /// ``moduleImportConditions``.
    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        guard !node.attributes.hasAttribute(named: "testable") else {
            return .skipChildren
        }
        // The module is the first path component: `import A.B.C` is a submodule
        // of `A`, and naming `A` is what puts `A.B.C`'s contents in scope.
        guard let module = node.path.first?.name.text, module != "Zerk" else {
            return .skipChildren
        }
        importsByFile[sourceFile, default: []].append((module, currentCondition))
        return .skipChildren
    }

    /// The modules the generated file needs, and the guards they sit under.
    ///
    /// Narrower than "every import in every file Zerk read": only files that put
    /// a name into the generated file which this module does not declare. A file
    /// registering nothing but local types has already been seen by the compiler
    /// in this module, so its imports buy the generated file nothing — and a
    /// module imported for no reason is a name the generated file could trip
    /// over that it never needed in scope.
    ///
    /// Erring towards inclusion in the one case that matters: a file that
    /// registered something whose names went unaccounted for is included, since
    /// a missing import is the failure automatic imports exist to remove, while
    /// a surplus one is only untidy. See ``mentionedNamesByFile``.
    func resolvedImports(declaredLocally: Set<String>)
    -> (modules: Set<String>, conditions: [String: Set<CompilationCondition>]) {
        var modules: Set<String> = []
        var conditions: [String: Set<CompilationCondition>] = [:]

        for (file, imports) in importsByFile {
            guard filesWithDeclarations.contains(file) else { continue }
            let names = mentionedNamesByFile[file]
            let contributes = names.map { !$0.subtracting(declaredLocally).isEmpty } ?? true
            guard contributes else { continue }
            for (module, condition) in imports {
                modules.insert(module)
                conditions[module, default: []].insert(condition)
            }
        }
        return (modules, conditions)
    }

    /// Every key spelling as it was written, from both places a key can come
    /// from: a local declaration and an `@ImportedInjectable`.
    ///
    /// The only input to ``KeyAliases/clashingBareNames(among:modules:)``, which
    /// is why it is one property here rather than an expression at each call
    /// site. It was the latter, reading ``keyDisplayNames`` alone, and that
    /// missed the case the clash rule was written for: two modules producing one
    /// bare name are almost always both *foreign*, so neither reaches
    /// `keyDisplayNames` and the two merged into a single key — reported as
    /// `'Config' is imported more than once`, against two imports that name
    /// different types.
    var writtenKeySpellings: [String] {
        Array(keyDisplayNames.keys) + importedInjectables.map(\.typeName)
    }

    private func collectAlias(macroName: String,
                              arguments: GenericArgumentClauseSyntax?,
                              syntax: Syntax) {
        guard macroName == "InjectableAlias" else {
            return
        }
        // A generic argument may be a value rather than a type (SE-0453); only
        // types can be alias keys.
        let types = (arguments?.arguments ?? []).compactMap { argument -> TypeSyntax? in
            guard case .type(let type) = argument.argument else {
                return nil
            }
            return type
        }
        let keys = types.map(\.normalizedTypeKey)
        guard keys.count >= 2 else {
            return
        }
        for type in types {
            keyNominalNames[type.normalizedTypeKey, default: []].formUnion(type.nominalNames)
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
        refuseValueFunction(node)
        collectMarkedGlobalFunction(node)

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
        let name = qualified(node.name.text)
        declaredAccessRanks[name, default: []].append(
            DeclaredAccessRecord(access: node.modifiers.accessRank, condition: currentCondition)
        )
        protocolPrimaryAssociatedTypeCounts[name] =
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
        declaredAccessRanks[qualified(node.declaredName), default: []].append(
            DeclaredAccessRecord(access: node.modifiers.accessRank, condition: currentCondition)
        )
        if !genericParameters.isEmpty {
            declaredGenericParameters[qualified(node.declaredName)] = genericParameters
        }

        let injectableAttributes = node.attributes.attributes(named: "Injectable")
        guard !injectableAttributes.isEmpty else { return }

        let location = self.location(for: Syntax(node))

        // A nested type's key and its construction are both recorded as the
        // *declared* name, so `struct Outer { @Injectable struct Inner {} }`
        // registers `Inner` and emits `Inner()` — neither of which names
        // anything from the generated file, which sits at file scope:
        // "cannot find type 'Inner' in scope".
        //
        // Refused rather than qualified, for now. Making it work means deciding
        // what a consumer writes for the key, and carrying that through the
        // alias and cross-module paths — a feature, not a repair. Refusing turns
        // an error inside generated code into one at the declaration.
        let enclosing = extensionStack + typeStack.map(\.name)
        guard enclosing.isEmpty else {
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: "@Injectable cannot be applied to '\(node.declaredName)', which is declared inside '\(enclosing.joined(separator: "."))'. Zerk registers a type under its own name and builds it from the generated file at file scope, where a nested name does not resolve — move it to the top level, or register a top-level factory with @Injectable that returns it.",
                location: location
            ))
            return
        }

        let isSingleton = node.attributes.hasAttribute(named: "Singleton")
        let typeScope = injectionScope(in: node.attributes,
                                       isSingleton: isSingleton,
                                       at: location)
        // The type's own parameters are not on `typeStack` yet — `enter` pushes
        // the frame only after this returns — so they are unioned in by hand.
        let scope = genericScope.union(genericParameters)

        for attribute in injectableAttributes {
            // `@Injectable` has no overload taking one, so Swift rejects this
            // first with "type 'Bool' has no member 'referenced'" — which names
            // neither the problem nor the fix. The plugin reads syntax rather
            // than resolving overloads, so it can still say what to write.
            if attribute.hasPositionalArgument {
                diagnostics.append(CodegenDiagnostic(
                    severity: .error,
                    message: "The injection method applies to values only. A type is built by a provider, not read from a declaration, so there is nothing to copy or reference — write it on an @InjectableValue instead.",
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

        if node.is(StructDeclSyntax.self) || node.is(EnumDeclSyntax.self) {
            // A shared value type hands each reader its own copy, so "one
            // instance" is not something the annotation can deliver — and the
            // silence would be the worst part, since the graph would look right
            // and mutations would go nowhere.
            if isSingleton {
                diagnostics.append(CodegenDiagnostic(
                    severity: .error,
                    message: "@Singleton can only be applied to reference types (class or actor).",
                    location: location
                ))
            } else if typeScope != nil {
                diagnostics.append(CodegenDiagnostic(
                    severity: .error,
                    message: "@Scoped can only be applied to reference types (class or actor). A value type is copied on every read, so keeping one for a scope would keep nothing.",
                    location: location
                ))
            }
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
        // `public:` and `primary:` both ride on the attribute that names the
        // key, so `@Injectable<A>(public: true) @Injectable<B>` exports A and
        // leaves B internal.
        var exportedKeys: [String: AttributeLocation] = [:]
        var primaryKeys: [String: AttributeLocation] = [:]

        for attribute in injectableAttributes {
            // Resolved once per attribute, and every flag below reads *this*.
            // These used to be three loops that each recomputed the key from
            // `genericArgumentKeys`, which silently disagreed with the
            // `parameterized:` branch: that files under a shape
            // (`Boxable<#0, #1>`) while a recomputation yields the written
            // `Boxable`. The flags then landed on a key nothing was registered
            // under, so a parameterized existential could not be exported and
            // could not win a conflict — the latter reported as "none is
            // primary" on a declaration that said `primary: true`.
            let keys: [String]
            let displayKeys: [String]
            // Paired with `keys` by index, like `displayKeys`.
            let nominalNames: [Set<String>]
            var isParameterized = false

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
                keys = [key]
                displayKeys = [display]
                // A parameterized existential names the protocol the attribute
                // wrote, holed out over the type's own parameters.
                nominalNames = [attribute.genericArgumentNominalNames.first ?? [node.declaredName]]
                isParameterized = true
            case .invalid:
                // Already reported. Falling through to the plain key path would
                // report a second, unrelated error about the same attribute.
                continue
            case .notRequested:
                let genericKeys = attribute.genericArgumentKeys
                keys = genericKeys.isEmpty ? [ownKey] : genericKeys
                // Paired with `keys` by index: the same types, canonicalized
                // with `any` kept. An unparameterized @Injectable keys on the
                // type itself, which is a bare identifier unless the type is
                // generic.
                displayKeys = genericKeys.isEmpty
                    ? [ownDisplayKey]
                    : attribute.genericArgumentDisplayKeys
                nominalNames = genericKeys.isEmpty
                    ? [[node.declaredName]]
                    : attribute.genericArgumentNominalNames
            }

            for (offset, key) in keys.enumerated() {
                injectableKeys[key] = location
                recordKey(display: displayKeys[offset],
                          nominalNames: nominalNames[offset],
                          for: key)
                if isParameterized {
                    parameterizedKeys[key] = location
                }
                if attribute.publicArgument.isTrue {
                    exportedKeys[key] = location
                }
                if attribute.primaryArgument.isTrue {
                    primaryKeys[key] = location
                }
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
                let initializerGenerics = initializer.declaredGenericParameters
                let initializerRequirements = initializer.declaredGenericRequirements
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
                        genericParameters: initializerGenerics,
                        genericConstraints: initializerRequirements
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
                            genericConstraints: initializerRequirements,
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
            let functionGenerics = function.declaredGenericParameters
            let functionRequirements = function.declaredGenericRequirements

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
                    genericConstraints: functionRequirements,
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

        var inferenceRefusal: String?
        if initializers.isEmpty {
            if var inferredInitializer = node.inferredSynthesizedInitializer(in: location,
                                                                            genericScope: scope) {
                inferredInitializer.isolation = typeIsolation
                initializers.append(inferredInitializer)
            } else if let (attribute, property) = node.unreadableStoredProperty {
                inferenceRefusal = "'@\(attribute)' on '\(property)' may change what the initializer takes — a property wrapper and an attached macro are spelled the same, and Zerk reads syntax rather than expanding them, so it will not guess."
            }
        }

        // The record's own parameters reach the generated file too.
        defer { note(parametersOf: types[types.count - 1]) }
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
                scope: typeScope,
                isolation: typeIsolation,
                genericParameters: genericParameters,
                parameterizedKeys: parameterizedKeys,
                initializerInferenceRefusal: inferenceRefusal,
                declaresSendable: node.declaresSendable,
                condition: currentCondition
            )
        )
    }

    /// The scope named by `@Scoped(.session)`, or `nil` when the type carries no
    /// usable one.
    ///
    /// Reports, rather than guesses, in the two cases where the attribute says
    /// something Zerk cannot act on: paired with `@Singleton`, and written with
    /// an argument that is not a leading-dot member access.
    private func injectionScope(in attributes: AttributeListSyntax,
                                isSingleton: Bool,
                                at location: AttributeLocation) -> InjectionScopeRecord? {
        guard let attribute = attributes.attributes(named: "Scoped").first else {
            return nil
        }

        if isSingleton {
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: "@Singleton and @Scoped both say how long one instance is kept, and they disagree — a singleton lives for the process, a scoped instance until its scope is reset. Keep the one you meant.",
                location: location
            ))
            return nil
        }

        guard let argument = attribute.labeledArguments.first(where: { $0.label == nil }),
              let member = argument.expression.as(MemberAccessExprSyntax.self),
              member.base == nil else {
            // See ``InjectionScopeRecord``: the leading-dot form is what makes
            // the scope both echoable into the generated storage and comparable
            // against another attribute's.
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: "@Scoped needs its scope written in leading-dot form — @Scoped(.session). Zerk reads this from source and never evaluates it, so it needs a name it can both compare and write back out.",
                location: location
            ))
            return nil
        }

        return InjectionScopeRecord(identity: member.declName.baseName.text)
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

    /// `@InjectableValue` on a function, which is refused.
    ///
    /// A value is *read* from a declaration and matched by key **and** name. A
    /// function with parameters is not that shape — it is something the graph
    /// builds, which `@Injectable` on a global or `static` func already
    /// registers, with the declaration as its provider.
    ///
    /// A function swept up by an enclosing `@InjectableValues` is skipped in
    /// silence rather than reported: the marker is a statement about the type,
    /// not a promise about every member, which is the same rule the property
    /// sweep follows. Only an explicit annotation is a promise, so only that is
    /// an error.
    private func refuseValueFunction(_ node: FunctionDeclSyntax) {
        let attributes = node.attributes.attributes(named: "InjectableValue")
        guard let first = attributes.first else {
            return
        }
        diagnostics.append(CodegenDiagnostic(
            severity: .error,
            message: InjectableValueRefusal.functionTarget,
            location: location(for: Syntax(first))
        ))
    }

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

        // Paired with `keys` by index, as the display spellings are: a written
        // `@InjectableValue<Key>` names the key outright, and otherwise the
        // annotation is the key.
        let nominalNames = genericKeys.isEmpty
            ? [annotation.type.nominalNames]
            : injectableAttributes.flatMap(\.genericArgumentNominalNames)

        for (offset, key) in keys.enumerated() {
            recordKey(display: displayKeys[offset], nominalNames: nominalNames[offset], for: key)
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
                    isExported: isExported,
                    condition: currentCondition
                )
            )
        }
    }

    /// Every nominal name a record's parameters mention, noted for this file.
    private func note(parametersOf record: TypeRecord) {
        var names: Set<String> = []
        for provider in record.defaultProviders + record.typedProviders.values.flatMap({ $0 }) {
            for parameter in provider.parameters {
                names.formUnion(parameter.typeNominalNames)
            }
        }
        for initializer in record.initializers {
            for parameter in initializer.parameters {
                names.formUnion(parameter.typeNominalNames)
            }
        }
        note(names)
    }

    /// Records that this file put `names` into something Zerk emits.
    private func note(_ names: Set<String>) {
        filesWithDeclarations.insert(sourceFile)
        guard !names.isEmpty else { return }
        mentionedNamesByFile[sourceFile, default: []].formUnion(names)
    }

    /// Records a key's spelling and the types that spelling mentions, together.
    ///
    /// Together, and through one function, because they answer for each other:
    /// the spelling is what `extension Zerk<Key>` is written as, and the names
    /// are what decides whether that extension's members may be `public`. A
    /// registration that recorded only the spelling passed the export check
    /// vacuously — the check falls back to the key *text*, which matches a bare
    /// type name and matches nothing at all for `Cache<Hidden>` or
    /// `any Alpha & Beta`. `@InjectableValue` did exactly that, and emitted a
    /// `public` member exposing an internal type.
    ///
    /// So there is no way to record one without the other. The spelling half
    /// prefers an `any` spelling over a bare one when declarations disagree.
    ///
    /// Only declarations that *establish* a key feed this. A parameter or an
    /// `@Injected` property keeps its own spelling at its own use site, which
    /// reaches the same specialization regardless.
    private func recordKey(display displayName: String, nominalNames: Set<String>, for key: String) {
        keyNominalNames[key, default: []].formUnion(nominalNames)
        note(nominalNames)

        guard let existing = keyDisplayNames[key] else {
            keyDisplayNames[key] = displayName
            return
        }
        if !existing.hasPrefix("any ") && displayName.hasPrefix("any ") {
            keyDisplayNames[key] = displayName
        }
    }

    /// Dot-joined enclosing declaration names, or `nil` at file scope.
    ///
    /// Extensions count: a `static var` in `extension Service` is read as
    /// `Service.config`, and the generated file has no `config` of its own.
    private var enclosingTypePath: String? {
        let path = extensionStack + typeStack.map(\.name)
        return path.isEmpty ? nil : path.joined(separator: ".")
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

        recordKey(display: annotation.type.displayTypeKey,
                  nominalNames: annotation.type.nominalNames,
                  for: annotation.type.normalizedTypeKey)

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
                isExported: isExported,
                condition: currentCondition
            )
        )
    }

    /// Records `@Injected` and `@InjectedDynamically` properties so the generator can
    /// check the chain behind each one.
    ///
    /// Both expand to a synchronous, non-throwing accessor, so a chain that turns
    /// out async, throwing, or cross-domain has to be reported against the
    /// property rather than left to fail in generated code. The two differ only
    /// in *when* they resolve, which the check does not care about.
    private func collectInjectedUse(_ node: VariableDeclSyntax) {
        let attributes = node.attributes.attributes(named: "Injected")
            + node.attributes.attributes(named: "InjectedDynamically")
        guard !attributes.isEmpty,
              let binding = node.bindings.first,
              let annotation = binding.typeAnnotation else {
            return
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
            var keyPathMemberName: String?
            if case .argumentList(let arguments)? = attribute.arguments,
               arguments.count == 1,
               arguments.first?.label == nil,
               let keyPath = arguments.first?.expression.as(KeyPathExprSyntax.self) {
                namesMemberDirectly = true
                // The property the path ends at. Read from the tree rather than
                // from the rendered text, which carries the leading dot and any
                // backticks the member's name needed.
                keyPathMemberName = keyPath.components.compactMap { component in
                    guard case .property(let property) = component.component else {
                        return nil
                    }
                    return property.declName.baseName.text
                }.last
            }
            injectedUses.append(InjectedUseRecord(
                // `@Injected<Foo>` states the key; otherwise it is the
                // property's own type.
                typeKey: attribute.genericArgumentKeys.first ?? typeKey,
                // Read from whichever type supplied the key, so the shape
                // and the key can never describe different types.
                typeKeyShape: attribute.genericArgumentTypes.first?.typeKeyShape
                    ?? injectedType.typeKeyShape,
                // Named so the diagnostic quotes the attribute the developer
                // actually wrote.
                macroName: "@\(attribute.name)",
                namesMemberDirectly: namesMemberDirectly,
                keyPathMemberName: keyPathMemberName,
                enclosingTypeName: enclosingTypePath,
                condition: currentCondition,
                location: location(for: Syntax(node))
            ))
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
            allAttributes: node.attributes,
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
        let ownGenerics = node.declaredGenericParameters
        collectInjectableDeclaration(
            node: Syntax(node),
            attributes: attributes,
            declaredName: node.name.text,
            producedType: returnType,
            genericParameters: ownGenerics,
            // A declaration's parameters are the *key's*, so a constraint the
            // produced type declares for itself is re-derived. One the function
            // adds on top is not: `@Injectable func make<X: Hashable, Y>() ->
            // Box<X, Y>` over a plain `Box<X, Y>` has nothing to re-derive it.
            genericRequirements: node.declaredGenericRequirements,
            parameters: node.signature.parameterClause.parameters
                .parameterRecords(locatedBy: { self.location(for: $0) },
                                  genericScope: genericScope.union(ownGenerics)),
            effects: ProviderEffects(from: node.signature.effectSpecifiers?.trimmedDescription),
            modifiers: node.modifiers,
            allAttributes: node.attributes,
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
                                              genericRequirements: [String] = [],
                                              parameters: [ParameterRecord],
                                              effects: ProviderEffects,
                                              modifiers: DeclModifierListSyntax,
                                              allAttributes: AttributeListSyntax,
                                              isProperty: Bool) {
        let location = self.location(for: node)

        // Global, or a type's static member. An instance member has no stable
        // reference the generated file could call, and a local one is not
        // visible to it at all.
        let enclosingPath = extensionStack + typeStack.map(\.name)
        guard enclosingPath.isEmpty || modifiers.isStatic else {
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: "@Injectable on a member needs it to be 'static': the generated file calls '\(qualified(declaredName))' directly, and an instance member has no such reference.",
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
            let names = written.isEmpty ? [producedType.nominalNames] : attribute.genericArgumentNominalNames
            for (offset, key) in keys.enumerated() {
                injectableKeys[key] = location
                recordKey(display: displays[offset], nominalNames: names[offset], for: key)
                if attribute.publicArgument.isTrue { exportedKeys[key] = location }
                if attribute.primaryArgument.isTrue { primaryKeys[key] = location }
            }
        }

        // The declaration's own isolation, read exactly as a type's or a
        // factory's is: a global-actor attribute, `@Isolated<A>` where the
        // plugin cannot see one, or `nonisolated`. Passing an empty attribute
        // list here meant an isolated declaration generated a `nonisolated`
        // member that called it — which does not compile.
        let stated = statedIsolation(modifiers: modifiers, attributes: allAttributes)
        validateStatedIsolation(
            stated,
            modifiers: modifiers,
            attributes: allAttributes,
            location: location
        )
        let declaredIsolation = stated.resolved(default: ambientIsolation)

        // A static member is reached by its qualified path. A global is not
        // reachable at all from inside the extension — the member being defined
        // shadows it — so it goes through a thunk declared at file scope.
        // Extensions included: a `static func` declared in `extension Service`
        // is `Service.make`, and calling a bare `make()` from the generated file
        // names nothing. `extensionStack` comes first because an extension can
        // only be outermost.
        let path = extensionStack + typeStack.map(\.name)
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
            isolation: declaredIsolation,
            isPrimary: false,
            genericParameters: [],
            genericConstraints: genericRequirements,
            memberName: memberName
        )

        // The produced type is a *name*, so the "reference types only" check a
        // type declaration gets cannot be made here — for `@Singleton` or for
        // `@Scoped`. Zerk reads syntax and cannot tell a class from a struct it
        // never sees. The developer's word is taken, exactly as `@Isolated`'s
        // is; keeping a value type shares a copy per read rather than an
        // instance, which is inert rather than unsound.
        var isSingleton = allAttributes.hasAttribute(named: "Singleton")
        var scope = injectionScope(in: allAttributes, isSingleton: isSingleton, at: location)
        if !genericParameters.isEmpty {
            // Same reason a generic type cannot be one: static stored
            // properties are illegal in a generic context, so there is nowhere
            // to keep an instance per specialization.
            if isSingleton {
                diagnostics.append(CodegenDiagnostic(
                    severity: .error,
                    message: GenericRefusal.singleton(type: baseName),
                    location: location
                ))
                isSingleton = false
            }
            if scope != nil {
                diagnostics.append(CodegenDiagnostic(
                    severity: .error,
                    message: GenericRefusal.scoped(type: baseName),
                    location: location
                ))
                scope = nil
            }
        }

        // The record's own parameters reach the generated file too.
        defer { note(parametersOf: types[types.count - 1]) }
        types.append(
            TypeRecord(
                name: baseName,
                injectableKeys: injectableKeys,
                exportedKeys: exportedKeys,
                primaryKeys: primaryKeys,
                defaultProviders: [provider],
                typedProviders: [:],
                initializers: [],
                isSingleton: isSingleton,
                scope: scope,
                isolation: provider.isolation,
                genericParameters: genericParameters,
                condition: currentCondition
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
        // Qualified by extensions too: a type declared inside `extension Outer`
        // is `Outer.Bar`, and generating `extension Bar` for it names something
        // that does not exist.
        let qualifiedName = qualified(node.declaredName)
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

    /// `@injected` members of an `extension`, whose overload belongs in an
    /// extension of the same type rather than at file scope.
    ///
    /// Kept apart from ``collectMarkedMembers(_:typeKind:typeIsGeneric:)``
    /// because an extension is not a declaration Zerk registers: it has no kind
    /// of its own, and the type it extends may be declared in another module.
    /// Only what can be generated without knowing that is collected.
    private func collectMarkedExtensionMembers(_ node: ExtensionDeclSyntax) {
        let extendedType = node.extendedType.trimmedDescription
        // `extension Cache` leaves `Cache`'s parameters in scope; `extension
        // Cache<Int>` binds them, and nothing generic is in scope there. Asked
        // of the tree — any generic argument clause anywhere in the spelling
        // binds — rather than of the text, which would be looking for a `<`.
        let bindsItsArguments = node.extendedType.containsGenericArguments
        let unboundExtendedTypeName = bindsItsArguments ? nil : extendedType
        let typeIsolation = statedIsolation(modifiers: node.modifiers, attributes: node.attributes)
            .resolved(default: ambientIsolation)

        for member in node.memberBlock.members {
            if let initializer = member.decl.as(InitializerDeclSyntax.self),
               initializer.signature.parameterClause.parameters.contains(where: {
                   $0.attributes.contains { element in
                       guard case .attribute(let attribute) = element else { return false }
                       return ConditionalCompilation.markerAttributes.contains(attribute.name)
                   }
               }) {
                // The generated overload would have to delegate with
                // `self.init(…)`, and a class's extension initializer must say
                // `convenience` while a struct's must not. Which one is a fact
                // about a type Zerk may never see.
                diagnostics.append(CodegenDiagnostic(
                    severity: .error,
                    message: "@injected parameters are not supported on an initializer declared in an extension of '\(extendedType)'. Zerk cannot tell whether the generated overload needs 'convenience', which depends on whether '\(extendedType)' is a class — declare the initializer on the type itself, or resolve the dependency in its body.",
                    location: location(for: Syntax(initializer))
                ))
                continue
            }

            guard let function = member.decl.as(FunctionDeclSyntax.self) else {
                continue
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
                typeName: extendedType,
                typeKind: nil,
                typeWhereClause: node.genericWhereClause?.trimmedDescription,
                requiresVisibleType: true,
                extendedTypeNominalNames: node.extendedType.nominalNames,
                // Not knowable here: an extension names no parameters of its
                // own, and the type it extends may be walked after it. Deferred
                // to emission through `unboundExtendedTypeName`, where every
                // declaration has been seen.
                //
                // A `where` clause is not the answer either. It constrains an
                // already-generic type rather than making one, and the generated
                // extension repeats the header, so the type's parameters stay in
                // scope either way — reading the clause as genericness refused
                // constrained extensions while accepting unconstrained ones.
                typeIsGeneric: false,
                unboundExtendedTypeName: unboundExtendedTypeName,
                typeAccess: node.modifiers.accessRank,
                isolation: .explicit(statedIsolation(
                    modifiers: function.modifiers,
                    attributes: function.attributes
                ).resolved(default: typeIsolation)),
                location: location(for: Syntax(function))
            )
        }
    }

    /// A **top-level** `func` carrying `@injected` parameters.
    ///
    /// Type members are collected by walking a type's member block; a global has
    /// no type to walk, so it is picked up here. Its overload is a file-scope
    /// function rather than an extension member — see
    /// ``MarkedMemberRecord/MemberKind/globalFunction(name:returnType:)``.
    ///
    /// "Top level" is read from the tree rather than from `typeStack`, because
    /// the stack is also empty inside a global `var`'s accessor — and a function
    /// declared there is local, so nothing outside the file could call the
    /// overload.
    private func collectMarkedGlobalFunction(_ node: FunctionDeclSyntax) {
        guard typeStack.isEmpty, Self.isTopLevel(node) else {
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
        collectMarkedMember(
            parameters: node.signature.parameterClause.parameters,
            kind: .globalFunction(
                name: node.name.text,
                returnType: node.signature.returnClause?.type.trimmedDescription
            ),
            effects: ProviderEffects(from: node.signature.effectSpecifiers?.trimmedDescription),
            memberIsGeneric: node.genericParameterClause != nil,
            modifiers: node.modifiers,
            typeName: nil,
            typeKind: nil,
            typeIsGeneric: false,
            // Nothing encloses it, so only its own modifiers constrain access.
            typeAccess: .public,
            isolation: .explicit(stated.resolved(default: ambientIsolation)),
            location: location
        )
    }

    /// Whether a declaration sits directly in the file rather than inside any
    /// body.
    ///
    /// Walked rather than counted: the chain to a top-level declaration is
    /// `CodeBlockItem` -> `CodeBlockItemList` -> `SourceFile`, and counting
    /// levels breaks the moment anything nests differently. Passing through a
    /// body of any kind means the declaration is local, so nothing outside the
    /// file could call an overload of it.
    private static func isTopLevel(_ node: some DeclSyntaxProtocol) -> Bool {
        var current = node.parent
        while let ancestor = current {
            if ancestor.is(SourceFileSyntax.self) {
                return true
            }
            if ancestor.is(CodeBlockSyntax.self)
                || ancestor.is(AccessorDeclSyntax.self)
                || ancestor.is(ClosureExprSyntax.self)
                // A member of a type or an extension. `typeStack` catches the
                // type case, since entering one pushes a frame — but an
                // `extension` pushes nothing, so without this a method in one
                // was collected as a global and the generated overload landed
                // at file scope, calling a method that is not there.
                || ancestor.is(MemberBlockSyntax.self) {
                return false
            }
            current = ancestor.parent
        }
        return false
    }

    /// Validates and records one member's parameter list.
    ///
    /// `@injected` is rejected on a parameter that already has a default, on a
    /// variadic, and on `inout`: the generated overload drops the parameter and
    /// supplies the value itself, which none of those forms can express.
    ///
    /// `typeIsGeneric` is what the *caller* knows. A type body knows it; an
    /// extension does not, and passes `unboundExtendedTypeName` instead so the
    /// question can be settled at emission, where every declaration has been
    /// seen. This block sat 120 lines away from here, above a different
    /// function — which is a fair part of why the refusal it describes had a
    /// hole in it.
    private func collectMarkedMember(parameters: FunctionParameterListSyntax,
                                     kind: MarkedMemberRecord.MemberKind,
                                     effects: ProviderEffects,
                                     memberIsGeneric: Bool,
                                     modifiers: DeclModifierListSyntax?,
                                     typeName: String?,
                                     typeKind: MarkedTypeKind?,
                                     typeWhereClause: String? = nil,
                                     requiresVisibleType: Bool = false,
                                     extendedTypeNominalNames: Set<String> = [],
                                     typeIsGeneric: Bool,
                                     unboundExtendedTypeName: String? = nil,
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
                // The specifier from the tree, not a prefix of the rendered
                // text: `inoutBuffer` starts with those five letters and is not
                // an `inout` anything. The same reason `nominalNames` is a tree
                // walk and `mentionedGenericParameters` says "never a substring
                // test" — a name the developer chose is not a token.
                if parameter.type.as(AttributedTypeSyntax.self)?.specifiers
                    .contains(where: { specifier in
                        specifier.as(SimpleTypeSpecifierSyntax.self)?
                            .specifier.tokenKind == .keyword(.inout)
                    }) == true {
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

        // The generated overload reproduces the extended type and every
        // unmarked parameter, so both put names into the generated file.
        note(extendedTypeNominalNames)
        note(Set(collected.flatMap { $0.parameter.typeNominalNames }))

        markedMembers.append(MarkedMemberRecord(
            typeName: typeName,
            typeKind: typeKind,
            kind: kind,
            typeWhereClause: typeWhereClause,
            requiresVisibleType: requiresVisibleType,
            extendedTypeNominalNames: extendedTypeNominalNames,
            unboundExtendedTypeName: unboundExtendedTypeName,
            condition: currentCondition,
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
}
