//
//  GeneratorOutputBuilder.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

import Foundation
import SharedToolkit

/// Turns resolved providers into the text of the generated file.
///
/// The last stage of the pipeline. For each key it emits an
/// `extension Zerk<Key>` holding one factory per provider — named after the
/// provider, so a key with several providers gets several members — plus a
/// single `inject()` entry point backed by the primary one. Alongside those go
/// the `@injected` overloads, the `Interjecting<Key>` protocols tests conform
/// to, and the `Sendable` checks singletons need.
///
/// Output is assembled as strings rather than syntax nodes, so nearly every
/// helper here returns a line or a fragment of one.
struct GeneratorOutputBuilder {
    let values: [InjectableValueRecord]
    /// Every (key, provider) pair: one generated member each.
    let resolutions: [ProviderResolution]
    /// The provider backing `inject()` for each key, as elected by
    /// `ProviderResolver`. Everything resolved *implicitly* — a dependency
    /// parameter, an `@injected` argument, an `@Injected` property — goes
    /// through this rather than through `resolutions`, because those all call
    /// `inject()`.
    var primaryResolutions: KeyIndex<ProviderResolution> = KeyIndex()
    var moduleAccessLevels: [String: Bool] = [:]
    var injectedUses: [InjectedUseRecord] = []
    var markedMembers: [MarkedMemberRecord] = []
    /// Injectable key -> the spelling to emit for it, from `SourceCollector`.
    /// Absent keys are emitted as themselves.
    var keyDisplayNames: [String: String] = [:]
    /// Modules `#ZerkImport` asked for. The generated file imports `Zerk` and
    /// nothing else by default, since the plugin cannot tell which module a name
    /// came from.
    var importedModules: Set<String> = []
    /// Modules asked for inside a `#if`, so the emitted `import` can carry the
    /// same guard. Absent means unconditional.
    var moduleImportConditions: [String: CompilationCondition] = [:]
    /// Every primary elected for a key, when `#if` clauses gave it a different
    /// winner per configuration. See ``ProviderResolutionResult/primaryVariants``.
    var primaryVariants: [String: [ProviderResolution]] = [:]

    ///
    /// They join what is emitted but never `primaryResolutions`: a value is
    /// reached by name, so it never becomes a key's `inject()`.
    /// How a key is written in the generated file.
    ///
    /// Differs from the key itself only in `any`: keys match with it stripped,
    /// because Zerk cannot tell an existential from a class, but the emitted
    /// spelling has to be the one the developer wrote.
    func displayName(for key: String) -> String {
        keyDisplayNames[key] ?? key
    }

    /// Puts generated lines under the `#if` its registration was written under.
    ///
    /// This is the whole of how Zerk handles conditional compilation: it does
    /// not decide which branch is live, it hands the decision back to the
    /// compiler by reproducing the guard. Empty blocks are dropped rather than
    /// wrapped — a `#if` around nothing is noise in a file people read.
    static func guarded(_ lines: [String], by condition: CompilationCondition) -> [String] {
        guard let text = condition.guardText, !lines.isEmpty else {
            return lines
        }
        return ["#if \(text)"] + lines + ["#endif"]
    }

    /// How to call a provider with its dependencies auto-resolved: the
    /// parameters a caller must still supply, the expressions to pass for all
    /// of them, and the effects the resulting call carries.
    struct WrapperPlan {
        let parameters: [ParameterRecord]
        let argumentExpressions: [String]
        let effects: ProviderEffects
        /// Bubbled requirements that clash with a parameter the provider already
        /// declares. Carried out rather than reported in place, because
        /// `wrapperPlan` runs many times per provider.
        var collisions: [BubbleResolver.Collision] = []

        /// Narrowing `rethrows` happens here rather than at each use, because
        /// `inject()`'s parameters are exactly this plan's: a provider's
        /// throwing closure may have been resolved away into the subtree, and
        /// `inject()` frequently ends up taking nothing at all.
        init(parameters: [ParameterRecord],
             argumentExpressions: [String],
             effects: ProviderEffects,
             collisions: [BubbleResolver.Collision] = []) {
            self.parameters = parameters
            self.argumentExpressions = argumentExpressions
            self.effects = effects.resolved(forParameters: parameters)
            self.collisions = collisions
        }
    }

    /// One kept instance — a `@Singleton`'s or a `@Scoped`'s — as it appears in
    /// the generated storage namespace.
    ///
    /// There is exactly one of these per *type*, which is the whole point:
    /// storing it per key would give a type injectable under two keys two
    /// instances, and "one instance" would only hold within a key.
    struct SharedStorage {
        let memberName: String
        let typeName: String
        /// The expression that builds the instance. It lands in the storage
        /// initializer for a singleton and in the *member* for a scoped type —
        /// see ``scopedStorageLines(_:)`` for why the two differ.
        let construction: String
        let isolation: ProviderIsolation
        /// `nil` for a singleton; the scope it is kept for otherwise.
        let scope: InjectionScopeRecord?
        /// What building the instance costs — the provider's own effects merged
        /// with its dependencies'.
        ///
        /// `.none` is the ordinary case and keeps the synchronous storage. Any
        /// effect at all moves the instance into a ``ZerkAsyncBox``, because
        /// neither a `static let` initializer nor a lock-held `build()` can
        /// await.
        var effects: ProviderEffects = .none
        /// The `#if` the owning type is declared under, which the storage slot
        /// is emitted under too — it names the type, so it cannot outlive it.
        var condition: CompilationCondition = .unconditional
    }

    /// The name of the generated namespace holding every process-lifetime
    /// instance.
    ///
    /// File-private, and prefixed to stay out of the way of anything a developer
    /// might declare — the module's own code reaches these through `Zerk<Key>`,
    /// never directly.
    static let singletonStorageEnumName = "_$zerk_singletons"

    /// The same, for the boxes `@Scoped` instances are kept in. A separate
    /// namespace rather than a shared one because the two hold different things:
    /// a singleton's member *is* the instance, a scoped one is a
    /// ``ZerkScopedBox`` that may or may not be holding one right now.
    static let scopedStorageEnumName = "_$zerk_scoped"

    /// Rebuilt on each access rather than stored — it is a pure function of
    /// `values` and `primaryResolutions`, both of which are immutable here.
    private var classifier: ParameterClassifier {
        ParameterClassifier(values: values, primaryResolutions: primaryResolutions)
    }

    /// Emits the complete file.
    ///
    /// Diagnostics accumulate rather than short-circuit, so one run reports
    /// every problem in the module instead of only the first.
    func build() -> GeneratorOutput {
        var output: [String] = [
            "// Generated by Zerk",
            "// Do not change by hand.",
            "",
            "import Zerk"
        ]
        // Sorted so the file is byte-identical between builds; `Zerk` stays
        // first because it is the one import that is never optional.
        for module in importedModules.sorted() {
            output += Self.guarded(["import \(module)"],
                                   by: moduleImportConditions[module] ?? .unconditional)
        }
        output.append("")
        var diagnostics: [CodegenDiagnostic] = []
        var points: [InterjectionPoint] = []
        var sendabilityChecks: [SendabilityCheck] = []
        var reportedAutoInjected = Set<String>()

        let classifier = self.classifier

        diagnostics += cycleDiagnostics()
        diagnostics += duplicateValueDiagnostics()

        // Built up front: the storage is per type while the members reading it
        // are per key, so it cannot be assembled from inside the per-key loop.
        let sharedStorage = sharedStorage(diagnostics: &diagnostics)

        // @Injected expands to a synchronous, non-throwing accessor; a chain
        // containing an async or throwing provider — or one that crosses an
        // isolation domain, which becomes async — cannot be resolved by it.
        for use in injectedUses where !use.namesMemberDirectly {
            guard let unique = primaryResolutions[use.typeKey, shape: use.typeKeyShape] else {
                continue
            }
            let plan = wrapperPlan(for: unique)
            if plan.effects.isAsync || plan.effects.isThrowing {
                diagnostics.append(CodegenDiagnostic(
                    severity: .error,
                    message: "'\(use.typeKey)' has an async, throwing, or cross-isolation dependency chain; \(use.macroName) cannot resolve it. Resolve manually with '\(plan.effects.callPrefix)Zerk<\(use.typeKey)>.inject()'.",
                    location: use.location
                ))
            }
        }

        let uniqueExternalSignatures = Set(primaryResolutions.values.map {
            macroSignatureKey(for: wrapperPlan(for: $0).parameters,
                              genericParameters: $0.memberGenericParameters)
        }).sorted()

        output += generatedInjectedMacroDeclarations(for: uniqueExternalSignatures)

        if !uniqueExternalSignatures.isEmpty {
            output.append("")
        }

        var thunkLines: [String] = []
        var emittedThunks = Set<String>()

        for value in values.sorted(by: { $0.name < $1.name }) {
            // An import matches parameters but declares nothing: the member, and
            // the interjection requirement that goes with it, belong to the
            // module that owns the value.
            guard !value.isImported else {
                continue
            }
            let readExpression: String
            switch value.injectionMethod {
            case .copied:
                guard let bodyText = value.bodyText else {
                    diagnostics.append(CodegenDiagnostic(
                        severity: .error,
                        message: "Injectable value '\(value.name)' must define a body.",
                        location: value.location
                    ))
                    continue
                }
                readExpression = bodyText
            case .referenced:
                // A copied body carries its own `try`/`await` verbatim; a
                // reference is a bare read, so the effects go on here. Wrapped
                // in `return` to match the statement form a copied body is in.
                readExpression = "return \(value.effects.callPrefix)\(referenceRead(for: value))"
                // A value registered under several keys yields one record per
                // key, all naming the same source, so thunks dedupe by name.
                if emittedThunks.insert(value.name).inserted {
                    thunkLines += Self.guarded(referenceThunkLines(for: value),
                                               by: value.condition)
                }
            }

            // A value is always property-shaped, so its point is just its name.
            let point = InterjectionPointName.text(member: value.name, parameters: [])
            let valueKeyText = value.keyText
            let guardLines = { (indent: String) in
                self.interjectionGuardLines(point: "`\(point)`", indent: indent)
            }

            let access = exportedAccessPrefix(isExported: value.isExported, injectableKey: value.typeKey)
            if value.isExported, access.isEmpty {
                diagnostics.append(inertPublicDiagnostic(
                    injectableKey: value.typeKey,
                    plural: false,
                    location: value.location
                ))
            }

            var valueLines: [String] = []
            valueLines.append("extension Zerk<\(valueKeyText)> {")
            valueLines.append("    \(value.isolation.declarationPrefix)\(access)static var \(value.name): \(valueKeyText) {")

            if value.injectionMethod == .referenced && value.isSettable {
                // Only a settable source earns a setter, and only then does the
                // member need an explicit accessor pair. Effects cannot reach
                // here: Swift has no effectful setter, so a settable value is
                // effect-free by construction.
                valueLines.append("        get {")
                valueLines += guardLines("            ")
                valueLines += Self.indented(readExpression, by: "            ")
                valueLines.append("        }")
                valueLines.append("        set {")
                valueLines.append("            \(referenceWrite(for: value, from: "newValue"))")
                valueLines.append("        }")
            } else if value.effects != .none {
                // An effectful value needs the explicit `get`, since that is the
                // only place `async`/`throws` can be written on a property. The
                // guard stays outside the effects — an interjected double is
                // read synchronously whatever the real value costs.
                valueLines.append("        get\(value.effects.declarationSuffix) {")
                valueLines += guardLines("            ")
                valueLines += Self.indented(readExpression, by: "            ")
                valueLines.append("        }")
            } else {
                valueLines += guardLines("        ")
                valueLines += Self.indented(readExpression, by: "        ")
            }

            valueLines.append("    }")
            valueLines.append("}")

            output += Self.guarded(valueLines, by: value.condition)
            output.append("")

            points.append(InterjectionPoint(scope: .key(value.typeKey),
                                            name: point,
                                            condition: value.condition))
        }

        // A global `@Injectable` declaration is reached through a private
        // forwarding function, for the same reason a referenced value is.
        //
        // Deduped by thunk name: a declaration registered under several keys has
        // one resolution per key but is still one declaration, and emitting its
        // thunk per key is `invalid redeclaration` in the generated file.
        for resolution in resolutions {
            guard case .explicit(let provider) = resolution.provider,
                  case .declaration(_, _, let thunk?) = provider.kind else {
                continue
            }
            guard emittedThunks.insert(thunk).inserted else {
                continue
            }
            thunkLines += Self.guarded(declarationThunkLines(for: resolution),
                                       by: resolution.condition)
        }

        if !thunkLines.isEmpty {
            output += thunkLines
            output.append("")
        }

        // Ahead of the extensions, which read from it.
        output += sharedStorageLines(sharedStorage)

        let grouped = Dictionary(grouping: resolutions, by: \.injectableKey)
        for injectableKey in grouped.keys.sorted() {
            // Sorted by name, then by source location. Swift's sort is not
            // stable, and providers sharing a member name is the normal case —
            // two marked initializers are both named after their type — so
            // without the tiebreaker their order is unspecified and the
            // generated file can differ between builds of identical source.
            let providers = grouped[injectableKey]!.sorted { lhs, rhs in
                let left = memberName(for: lhs)
                let right = memberName(for: rhs)
                if left != right {
                    return left < right
                }
                return lhs.provider.location < rhs.provider.location
            }

            // Keyed on name *and* parameter shape, because same-named members
            // are how multiple providers coexist: two marked initializers are
            // both named after their type, and generate overloads that Swift
            // tells apart exactly as it tells the initializers apart. Only an
            // identical shape is a genuine redeclaration.
            // A companion `var` can only exist where the member name is used
            // once: two providers sharing it are distinguished by their
            // parameters, which an argument-free `var` has none of.
            var memberNameCounts: [String: Int] = [:]
            for provider in providers {
                memberNameCounts[memberName(for: provider), default: 0] += 1
            }

            // Seeded with this key's property values, whose members are
            // argument-free and so occupy a provider's `name()` signature. They
            // are emitted from their own loop, so without this a value named
            // like a provider's member is only caught by `invalid
            // redeclaration` in the generated file.
            var seenMemberSignatures: [String: (owner: String, condition: CompilationCondition)] = [:]
            var valueOwnedSignatures = Set<String>()
            for value in values
            where value.typeKey == injectableKey && !value.isImported {
                let signature = "\(value.name)()"
                seenMemberSignatures[signature] = ("the @InjectableValue '\(value.name)'", value.condition)
                valueOwnedSignatures.insert(signature)
            }

            for provider in providers {
                let name = memberName(for: provider)
                for signature in memberSignatureKeys(for: provider, name: name) {
                    // Two members of one name are only a redeclaration where
                    // both are compiled. Registered in different clauses of one
                    // `#if`, they are one member with two definitions — which is
                    // the ordinary reason to write a `#if` at all.
                    if let existing = seenMemberSignatures[signature],
                       !CompilationCondition.areExclusive(existing.condition, provider.condition) {
                        let involvesValue = valueOwnedSignatures.contains(signature)
                        diagnostics.append(CodegenDiagnostic(
                            severity: .error,
                            message: "Generated member '\(name)' for '\(provider.typeName)' collides with \(existing.owner) in Zerk<\(displayName(for: injectableKey))>: same name, same parameters. \(Self.collisionRemedy(involvesValue: involvesValue))",
                            location: provider.provider.location
                        ))
                    } else {
                        seenMemberSignatures[signature] = ("'\(provider.typeName)'", provider.condition)
                    }
                }
            }

            let pointNames = interjectionPointNames(for: providers)

            // A generic key binds `Injectable` per member, in a where clause,
            // so its block cannot bind it in the header: `extension
            // Zerk<Cache<E>>` has no `E` to name.
            // A parameterized existential did not exist before iOS 16, and the
            // plugin cannot read the target's deployment version — the same
            // reason `ZerkSettings.json` exists. Emitted unconditionally: it
            // costs a caller nothing to be told a member is available from 16,
            // and without it a target deploying lower would not build at all.
            var availabilityLines: [String] = []
            if providers.contains(where: \.isParameterizedExistential) {
                availabilityLines.append(Self.parameterizedExistentialAvailability)
            }
            // The extension header names the key, so it can only be emitted
            // where the key's own type exists. Guarding it by what every
            // provider shares covers the case that matters — a type registered
            // only inside `#if DEBUG`, whose key is that same type — while
            // leaving a `#if`/`#else` swap of one protocol key unguarded, since
            // there the key exists either way and only the members differ.
            let sharedCondition = CompilationCondition.commonPrefix(of: providers.map(\.condition))
            var keyLines: [String] = []

            keyLines.append(providers.first?.keyIsGeneric == true
                ? "extension Zerk {"
                : "extension Zerk<\(displayName(for: injectableKey))> {")

            for provider in providers {
                let classification = classifier.classify(provider)

                for collision in wrapperPlan(for: provider).collisions {
                    let identity = "collision|\(provider.typeName)|\(collision.own.name)|\(collision.requirement.typeKey)"
                    guard reportedAutoInjected.insert(identity).inserted else {
                        continue
                    }
                    diagnostics.append(CodegenDiagnostic(
                        severity: .error,
                        message: "Resolving '\(collision.dependencyName)' needs '\(collision.requirement.name): \(collision.requirement.typeName)', which collides with '\(provider.typeName)'s own '\(collision.own.name)' parameter. Mark it @injectable to feed the same value to both.",
                        location: collision.own.location ?? provider.provider.location
                    ))
                }

                // Deduped by parameter position: a provider serving two keys is
                // classified once per key, and the parameter is unresolvable in
                // both — but the developer wrote it once.
                for parameter in classification.unresolvedAutoInjected {
                    let identity = "\(provider.typeName)|\(parameter.name)|\(parameter.location.map(String.init(describing:)) ?? "")"
                    guard reportedAutoInjected.insert(identity).inserted else {
                        continue
                    }
                    diagnostics.append(CodegenDiagnostic(
                        severity: .error,
                        message: "@autoinjected parameter '\(parameter.name)' cannot be resolved: '\(parameter.typeKey)' is not injectable in this module. Declare it @Injectable, or drop @autoinjected and pass it in.",
                        location: parameter.location ?? provider.provider.location
                    ))
                }

                sendabilityChecks += classification.crossDomainSharedDependencies.map {
                    SendabilityCheck(
                        shared: $0,
                        consumerTypeName: provider.typeName,
                        consumerIsolation: provider.isolation,
                        condition: provider.condition
                    )
                }

                guard let lines = memberLines(
                    for: provider,
                    injectableKey: injectableKey,
                    classification: classification,
                    hasUniqueMemberName: memberNameCounts[memberName(for: provider)] == 1,
                    sharedStorage: sharedStorage,
                    pointNames: pointNames,
                    points: &points,
                    diagnostics: &diagnostics
                ) else {
                    continue
                }

                keyLines += Self.guarded(lines,
                                         by: provider.condition.dropping(prefix: sharedCondition))
                keyLines.append("")
            }

            // One `inject()` per configuration that elected its own primary.
            // Their guards are mutually exclusive by construction — that is what
            // made them separate elections — so at most one is ever compiled.
            for primary in injectVariants(for: injectableKey, diagnostics: &diagnostics) {
                keyLines += Self.guarded(
                    injectLines(
                        for: primary,
                        injectableKey: injectableKey,
                        classification: classifier.classify(primary),
                        diagnostics: &diagnostics
                    ),
                    by: primary.condition.dropping(prefix: sharedCondition)
                )
                keyLines.append("")
            }

            keyLines.append("}")

            output += Self.guarded(availabilityLines + keyLines, by: sharedCondition)
            output.append("")
        }

        output += markedMemberLines(diagnostics: &diagnostics)
        output += interjectionPointLines(points: points)
        output += sendabilityCheckLines(sendabilityChecks)

        return GeneratorOutput(
            output: output.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n",
            diagnostics: diagnostics,
            usesIsolatedDefaultArguments: resolutions.contains {
                classifier.classify($0).usesIsolatedDefaultArgument
            }
        )
    }

    // MARK: - Provider members

    /// Emits the member(s) for one provider.
    ///
    /// When every dependency is defaultable this is a single member, exactly as
    /// before. When at least one dependency has to be resolved in the body (an
    /// effectful or cross-domain resolution) it becomes two:
    ///
    /// - the **explicit** variant, taking those dependencies as required
    ///   parameters. It carries the interjection guard and the construction, so
    ///   there is exactly one of each per provider.
    /// - the **resolving** variant, which omits them, resolves them, and
    ///   delegates. It inherits the merged effects.
    ///
    /// Their arities always differ — the explicit variant's extra parameters are
    /// required — so the overload is never ambiguous.
    private func memberLines(for provider: ProviderResolution,
                             injectableKey: String,
                             classification: ProviderClassification,
                             hasUniqueMemberName: Bool,
                             sharedStorage: [String: SharedStorage],
                             pointNames: [String: String],
                             points: inout [InterjectionPoint],
                             diagnostics: inout [CodegenDiagnostic]) -> [String]? {
        let memberName = memberName(for: provider)
        let isolation = provider.isolation
        let allParameters = provider.provider.parameters
        // `rethrows` only survives onto a signature that kept a throwing
        // function parameter to rethrow from.
        let ownEffects = provider.provider.effects.resolved(forParameters: allParameters)
        let keyText = displayName(for: injectableKey)
        let access = exportedAccessPrefix(for: provider, injectableKey: injectableKey)

        if provider.isShared {
            // No entry means the instance had no legal form and the reason was
            // already reported against the type; emitting a member that reads
            // storage which does not exist would bury that behind a compile
            // error in generated code.
            guard let storage = sharedStorage[provider.typeName] else {
                return nil
            }
            let point = pointNames[pointIdentity(for: provider)] ?? memberName
            points.append(InterjectionPoint(scope: .key(injectableKey),
                                            name: point,
                                            condition: provider.condition))
            return sharedInstanceLines(
                for: provider,
                injectableKey: injectableKey,
                access: access,
                memberName: memberName,
                point: point,
                storage: storage
            )
        }

        let defaults = classification.defaultExpressions
        let generics = genericClauses(for: provider, injectableKey: injectableKey)
        // A property takes no generic parameters, so a generic key's members are
        // always functions — even the argument-free ones, which lose the
        // `Zerk<Cache<String>>.cache` spelling a concrete key gets.
        let usesFunctionShape =
            provider.memberIsGeneric || !allParameters.isEmpty || ownEffects.isAsync || ownEffects.isThrowing

        var lines: [String] = []

        if usesFunctionShape {
            let signature = parameterClause(parameters: allParameters, defaults: defaults)
            // A property-shaped provider is read, not called: `Config.session`,
            // never `Config.session()`. It can still reach the function branch,
            // since `async`/`throws` force it there with no parameters at all.
            let construction = provider.provider.isPropertyShaped
                ? "\(ownEffects.callPrefix)\(builderConstruction(for: provider))"
                : "\(ownEffects.callPrefix)\(builderConstruction(for: provider))(\(builderArguments(allParameters, useParameterNames: true, defaults: defaults)))"
            lines.append("    \(isolation.declarationPrefix)\(access)static func \(memberName)\(generics.parameters)\(signature)\(ownEffects.declarationSuffix) -> \(keyText)\(generics.whereClause) {")
            let point = pointNames[pointIdentity(for: provider)] ?? memberName
            lines += interjectionGuardLines(for: provider, point: point)
            lines.append("        return \(construction)")
            lines.append("    }")

            if let scope = pointScope(for: provider, injectableKey: injectableKey) {
                points.append(InterjectionPoint(scope: scope,
                                                name: point,
                                                condition: provider.condition))
            }

            // The companion `var` is a property too, so it goes the same way.
            if hasUniqueMemberName, !provider.memberIsGeneric {
                lines += keyPathReachableVariantLines(
                    memberName: memberName,
                    keyText: keyText,
                    access: access,
                    isolation: isolation,
                    ownEffects: ownEffects,
                    classification: classification
                )
            }
        } else {
            let construction = provider.provider.isPropertyShaped
                ? "\(ownEffects.callPrefix)\(builderConstruction(for: provider))"
                : "\(ownEffects.callPrefix)\(builderConstruction(for: provider))()"
            lines.append("    \(isolation.declarationPrefix)\(access)static var \(memberName): \(keyText) {")
            let point = pointNames[pointIdentity(for: provider)] ?? memberName
            lines += interjectionGuardLines(for: provider, point: point)
            lines.append("        return \(construction)")
            lines.append("    }")

            if let scope = pointScope(for: provider, injectableKey: injectableKey) {
                points.append(InterjectionPoint(scope: scope,
                                                name: point,
                                                condition: provider.condition))
            }
        }

        guard classification.requiresSplit else {
            return lines
        }

        // Resolving variant: same name, without the body-resolved parameters.
        let resolvingParameters = classification.resolvingVariantParameters
        let resolvingEffects = ownEffects
            .merged(with: classification.dependencyEffects)
            .resolved(forParameters: resolvingParameters)

        let resolvingSignature = parameterClause(parameters: resolvingParameters, defaults: defaults)
        let forwardedArguments = classification.parameters.map { classified -> String in
            let expression: String
            if case .bodyResolved(let resolved, _) = classified.binding {
                expression = resolved
            } else {
                expression = classified.parameter.name
            }
            if let label = classified.parameter.label {
                return "\(label): \(expression)"
            }
            return expression
        }
        .joined(separator: ", ")

        lines.append("")
        lines.append("    \(isolation.declarationPrefix)\(access)static func \(memberName)\(generics.parameters)\(resolvingSignature)\(resolvingEffects.declarationSuffix) -> \(returnClause(for: provider, key: keyText, parameters: resolvingParameters, classification: classification))\(generics.whereClause) {")
        lines.append("        \(ownEffects.callPrefix)\(memberName)(\(forwardedArguments))")
        lines.append("    }")

        return lines
    }

    /// `public ` when `@Injectable(public: true)` asked for it and the key can
    /// carry it.
    ///
    /// `public:` publicises every generated member for the key, not just
    /// `inject()`: a consuming module that wants one specific member — through
    /// `@Injected(\.staging)`, say — needs to see it. The key type itself has to
    /// be public, since a public member cannot expose an internal type.
    private func exportedAccessPrefix(for provider: ProviderResolution,
                                      injectableKey: String) -> String {
        exportedAccessPrefix(isExported: provider.isExported, injectableKey: injectableKey)
    }

    /// The same decision for an injectable *value*, which has no
    /// `ProviderResolution` behind it. The key is all that appears in the
    /// member's signature, so the rule is identical: the value's own declaration
    /// may stay internal, since a public accessor's *body* may read it.
    private func exportedAccessPrefix(isExported: Bool, injectableKey: String) -> String {
        guard isExported, moduleAccessLevels[injectableKey] != false else {
            return ""
        }
        return "public "
    }

    /// The warning raised when `public: true` cannot be honoured, worded for
    /// whichever declaration asked.
    private func inertPublicDiagnostic(injectableKey: String,
                                       plural: Bool,
                                       location: AttributeLocation) -> CodegenDiagnostic {
        CodegenDiagnostic(
            severity: .warning,
            message: "@Injectable(public: true) has no effect: '\(injectableKey)' is not public, so the generated \(plural ? "members cannot be public" : "member cannot be public").",
            location: location
        )
    }

    /// Emits an argument-free `static var` alongside a function-shaped member
    /// whose parameters Zerk resolves in full.
    ///
    /// The function stays and keeps the construction and the interjection guard;
    /// this only delegates to it. That is what makes the pair legal — `live` and
    /// `live(dep:)` are different names, where `live` and `live()` would be a
    /// redeclaration — and it keeps one construction site, one guard and one
    /// interjection requirement.
    ///
    /// Its purpose is reach: `@Injected(\.live)` takes a key path, and a key path
    /// can name a property but not a method. The conditions below are exactly
    /// what makes such a property expressible:
    ///
    /// - **parameters, all resolvable** — with none the member is already a
    ///   `var`, and with an unresolvable one there is nothing to default it to.
    /// - **no effects, its own or its dependencies'** — Swift refuses to form a
    ///   key path to an `async` or `throws` property, so an effectful variant
    ///   could not be reached anyway; and for an argument-free effectful member
    ///   the two names would collide.
    private func keyPathReachableVariantLines(memberName: String,
                                              keyText: String,
                                              access: String,
                                              isolation: ProviderIsolation,
                                              ownEffects: ProviderEffects,
                                              classification: ProviderClassification) -> [String] {
        guard !classification.parameters.isEmpty,
              classification.isFullyResolvable,
              ownEffects == .none,
              classification.dependencyEffects == .none else {
            return []
        }

        return [
            "",
            "    \(isolation.declarationPrefix)\(access)static var \(memberName): \(keyText) {",
            "        \(memberName)()",
            "    }"
        ]
    }

    // MARK: - Kept instances

    /// Builds the entry for every `@Singleton` and `@Scoped` in the module,
    /// keyed by the type that owns it.
    ///
    /// One entry per *type*, not per key. `Zerk<A>` and `Zerk<B>` are distinct
    /// generic specializations with distinct static storage, so an instance
    /// stored on them directly would exist once per key — "one instance" would
    /// only hold within a key, which is not what either annotation says.
    ///
    /// The two lifetimes share this pass because everything it decides is about
    /// *sharing* rather than duration: which type owns the storage, what the
    /// storage is called, and whether the instance can be built at all. Where
    /// they part company is emission — see ``sharedStorageLines(_:)``.
    ///
    /// Runs ahead of the per-key emission because the validation is per type
    /// too: checking inside the member loop would report the same unbuildable
    /// instance once for every key it claims.
    private func sharedStorage(diagnostics: inout [CodegenDiagnostic]) -> [String: SharedStorage] {
        var storage: [String: SharedStorage] = [:]
        var attempted = Set<String>()
        var claimedNames: [String: String] = [:]
        let classifier = self.classifier

        // Sorted so the enum's members, and any diagnostic, land in the same
        // order on every build.
        let shared = resolutions
            .filter(\.isShared)
            .sorted { ($0.typeName, $0.injectableKey) < ($1.typeName, $1.injectableKey) }

        for resolution in shared {
            // The resolver has already proved every key of this type resolves to
            // the same provider, so the first one seen speaks for all of them.
            guard attempted.insert(resolution.typeName).inserted else {
                continue
            }
            guard let entry = sharedStorageEntry(
                for: resolution,
                classification: classifier.classify(resolution),
                diagnostics: &diagnostics
            ) else {
                continue
            }

            // Checked across both namespaces rather than within each. A type is
            // only ever in one of them, so a collision means two type names that
            // lower-camel-case alike — a problem wherever they landed, and one
            // whose fix does not depend on which enum it was.
            if let owner = claimedNames[entry.memberName] {
                let enumName = entry.scope == nil
                    ? Self.singletonStorageEnumName
                    : Self.scopedStorageEnumName
                diagnostics.append(CodegenDiagnostic(
                    severity: .error,
                    message: "\(resolution.sharingAttributeName) '\(resolution.typeName)' and '\(owner)' both store as '\(entry.memberName)' in \(enumName). Rename one of the types.",
                    location: resolution.provider.location
                ))
                continue
            }

            claimedNames[entry.memberName] = resolution.typeName
            storage[resolution.typeName] = entry
        }

        return storage
    }

    /// Validates one kept instance and describes the storage to emit for it.
    ///
    /// The three rules are the same for both lifetimes, and for one underlying
    /// reason: the instance is built exactly once, from a synchronous
    /// expression, with no help from the caller. The *reason it must be
    /// synchronous* differs, so each says its own — a singleton's storage is a
    /// `static let`, while a scoped instance is built under the box's lock.
    private func sharedStorageEntry(for provider: ProviderResolution,
                                    classification: ProviderClassification,
                                    diagnostics: inout [CodegenDiagnostic]) -> SharedStorage? {
        let attribute = provider.sharingAttributeName

        if !classification.isFullyResolvable {
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: "\(attribute) injectables cannot accept external arguments. The instance is built once and handed to every caller, so there is no answer to which caller's arguments it was built with.",
                location: provider.provider.location
            ))
            return nil
        }

        diagnostics += stalenessDiagnostics(for: provider, classification: classification)

        // Everything resolvable, not just what a default argument could hold: an
        // effectful construction is emitted inside the box's closure, where an
        // `await` is legal.
        let defaults = classification.resolvedExpressions

        // Every other provider is *called*, so the parentheses are
        // unconditional there. An `@Injectable` static property is read, and
        // `Container.session()` calls a property that is not a function.
        let construction = provider.provider.isPropertyShaped
            ? builderConstruction(for: provider)
            : "\(builderConstruction(for: provider))(\(builderArguments(provider.provider.parameters, useParameterNames: false, defaults: defaults)))"

        return SharedStorage(
            memberName: provider.typeName.memberNameForType,
            typeName: provider.sharedStorageTypeName,
            construction: construction,
            isolation: provider.isolation,
            scope: provider.scope,
            effects: provider.provider.effects.merged(with: classification.dependencyEffects),
            condition: provider.condition
        )
    }

    /// Reports a kept instance that would outlive a scoped dependency and go on
    /// holding it after that scope is reset.
    ///
    /// The hazard is one-directional and worth stating plainly: `Zerk.reset(_:)`
    /// clears the *box*, not the references already handed out. Anything longer-
    /// lived that captured the old instance keeps using it, silently, while
    /// everything resolved afterwards sees the new one. Two of those get a
    /// diagnostic, and they get different ones because Zerk knows different
    /// amounts about them.
    ///
    /// - **A singleton holding a scoped instance is an error.** A singleton is
    ///   built once and never dropped, so it outlives *every* scope by
    ///   construction. There is no configuration in which this is what someone
    ///   meant.
    /// - **A scope holding a different scope's instance is a warning.** Zerk
    ///   knows the two scopes are not the same one; it has no idea which is
    ///   reset first, or whether either ever is. `.request` inside `.session` is
    ///   a bug; `.session` inside `.application` is fine. Only the developer
    ///   knows which they wrote, so this reports without failing the build.
    ///
    /// A transient dependent needs neither: it is rebuilt on every resolution
    /// and so can never be the one holding something stale.
    private func stalenessDiagnostics(for provider: ProviderResolution,
                                      classification: ProviderClassification)
    -> [CodegenDiagnostic] {
        let scoped = classification.scopedDependencies
        guard !scoped.isEmpty else {
            return []
        }

        func describe(_ dependencies: [SharedDependency]) -> String {
            dependencies
                .map { "@Scoped(.\($0.scope ?? "")) '\($0.typeName)'" }
                .joined(separator: ", ")
        }

        if provider.isSingleton {
            return [CodegenDiagnostic(
                severity: .error,
                message: "@Singleton '\(provider.typeName)' depends on \(describe(scoped)). A singleton is built once and never dropped, so after that scope is reset it would still be holding the instance from before. Give '\(provider.typeName)' the same @Scoped lifetime, or resolve the dependency per use with @InjectedDynamically.",
                location: provider.provider.location
            )]
        }

        guard let ownScope = provider.scope?.identity else {
            return []
        }
        let foreign = scoped.filter { $0.scope != ownScope }
        guard !foreign.isEmpty else {
            // Same scope: both are dropped by the same reset and both are
            // rebuilt on the next resolution, so nothing goes stale.
            return []
        }

        return [CodegenDiagnostic(
            severity: .warning,
            message: "@Scoped(.\(ownScope)) '\(provider.typeName)' depends on \(describe(foreign)). Resetting that scope alone would leave '\(provider.typeName)' holding the old instance. Zerk can see the scopes differ but not which outlives which, so this is a warning: put them in one scope, or resolve the dependency per use with @InjectedDynamically.",
            location: provider.provider.location
        )]
    }

    /// Emits both storage namespaces, or nothing for the ones the module has no
    /// entries for.
    private func sharedStorageLines(_ storage: [String: SharedStorage]) -> [String] {
        let entries = storage.values.sorted { $0.memberName < $1.memberName }
        return singletonStorageLines(entries.filter { $0.scope == nil })
            + scopedStorageLines(entries.filter { $0.scope != nil })
    }

    /// The namespace holding every process-lifetime instance.
    private func singletonStorageLines(_ entries: [SharedStorage]) -> [String] {
        guard !entries.isEmpty else {
            return []
        }

        var lines = ["private enum \(Self.singletonStorageEnumName) {"]

        for entry in entries {
            // An effectful build cannot happen in a `static let` initializer, so
            // the slot holds a box and the construction moves to the member.
            // The box is Sendable, so the `nonisolated(unsafe)` the plain form
            // needs does not apply — but the slot is still pinned to the
            // member's isolation, for the reason `scopedStorageLines` gives.
            guard entry.effects == .none else {
                lines += Self.guarded(
                    ["    \(entry.isolation.declarationPrefix)static let \(entry.memberName) = ZerkAsyncBox<\(entry.typeName)>()"],
                    by: entry.condition)
                continue
            }

            switch entry.isolation {
            case .nonisolated:
                // `static let` initialization is thread-safe in the Swift
                // runtime; `nonisolated(unsafe)` acknowledges that sharing the
                // instance across isolation domains is the documented contract
                // of @Singleton (Swift 6 would otherwise require the stored type
                // to be Sendable).
                lines += Self.guarded(
                    ["    nonisolated(unsafe) static let \(entry.memberName): \(entry.typeName) = \(entry.construction)"],
                    by: entry.condition)
            case .globalActor(let name):
                // Global-actor isolation already protects the storage, so no
                // `nonisolated(unsafe)` escape hatch is needed here.
                lines += Self.guarded(
                    ["    @\(name) static let \(entry.memberName): \(entry.typeName) = \(entry.construction)"],
                    by: entry.condition)
            }
        }

        lines.append("}")
        lines.append("")
        return lines
    }

    /// The namespace holding one ``ZerkScopedBox`` per `@Scoped` type.
    ///
    /// The **construction is deliberately not here** — it goes on the member
    /// instead, so it runs in that member's isolation domain. A `@MainActor`
    /// type's box would otherwise have to carry a `@MainActor` closure, and
    /// could then only be read from the main actor, including by
    /// `Zerk.reset(_:)`, which must not be.
    ///
    /// What *is* here, and differs from the singleton namespace above, is the
    /// isolation annotation. `ZerkScopedBox` is `Sendable`, so no
    /// `nonisolated(unsafe)` is wanted — the compiler warns that it is
    /// unnecessary — but the slot still has to be pinned, because
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION` would otherwise make an unannotated one
    /// `@MainActor` and put it out of reach of a nonisolated member. Pinned to
    /// the *member's* isolation, since that is the only thing that reads it.
    ///
    /// The scope is echoed exactly as it was written at the attribute, so the
    /// value the box compares against is the developer's own. See
    /// ``InjectionScopeRecord``.
    private func scopedStorageLines(_ entries: [SharedStorage]) -> [String] {
        guard !entries.isEmpty else {
            return []
        }

        var lines = [
            // The one combination this cannot pin its way out of: a nonisolated
            // slot reading a scope that the ambient default made isolated. The
            // fix is a word, and it is cheaper to say it here than to let the
            // compiler report it against a line nobody wrote.
            "// A scope named from a nonisolated slot must itself be nonisolated. Under",
            "// SWIFT_DEFAULT_ACTOR_ISOLATION, write `nonisolated static let session = …`.",
            "private enum \(Self.scopedStorageEnumName) {"
        ]

        for entry in entries {
            let scope = entry.scope?.expression ?? ""
            // `ZerkScopedBox` builds under its lock, which an effectful build
            // cannot do. Same storage, same reset, different box.
            let box = entry.effects == .none ? "ZerkScopedBox" : "ZerkAsyncBox"
            lines += Self.guarded(
                ["    \(entry.isolation.declarationPrefix)static let \(entry.memberName) = \(box)<\(entry.typeName)>(scope: \(scope))"],
                by: entry.condition)
        }

        lines.append("}")
        lines.append("")
        return lines
    }

    /// Emits one key's view onto a kept instance.
    ///
    /// The interjection guard lives here rather than in the storage, which it
    /// cannot: the guard is per key — `InterjectingA` and `InterjectingB` are
    /// different protocols — while the storage is per type. Consulting it on each
    /// read is the better semantics anyway: a test double installed after the
    /// first resolution now takes effect, and interjecting a kept instance never
    /// builds the real one at all.
    ///
    /// A singleton reads its storage; a scoped type asks its box, handing over
    /// the construction to run if the box is empty. That closure is the reason a
    /// scoped member is emitted here rather than sharing the singleton's line:
    /// it is the *member* that knows how to build, and the *box* that knows
    /// whether to.
    private func sharedInstanceLines(for provider: ProviderResolution,
                                     injectableKey: String,
                                     access: String,
                                     memberName: String,
                                     point: String,
                                     storage: SharedStorage) -> [String] {
        let namespace = storage.scope == nil
            ? Self.singletonStorageEnumName
            : Self.scopedStorageEnumName

        guard storage.effects == .none else {
            // Reading an effectful kept instance is `async` even when only the
            // construction throws: the box coordinates concurrent callers onto
            // one build, and joining that build is what suspends.
            let read = Self.keptReadEffects(storage.effects)
            var lines = [
                "    \(provider.isolation.declarationPrefix)\(access)static func \(memberName)()\(read.declarationSuffix) -> \(displayName(for: injectableKey)) {"
            ]
            lines += interjectionGuardLines(point: "`\(point)`")
            // Two effect prefixes, and they are not the same one: the outer
            // belongs to joining the build, the inner to the construction the
            // box is handed.
            //
            // The inner is the provider's own effects *plus a hop into its own
            // domain*. The closure is `@Sendable`, so it does not inherit the
            // member's isolation the way `ZerkScopedBox`'s synchronous closure
            // does — it runs on the build's task, and reaching a global-actor
            // isolated initializer from there costs an `await`. What it must
            // not include is the dependencies' effects: those already carry
            // their own `try`/`await` inside the construction, and prefixing
            // the whole expression again would await a call that never
            // suspends.
            let construction = provider.provider.effects.merged(
                with: ProviderEffects(isAsync: provider.isolation.isGlobalActor, isThrowing: false))
            lines.append("        return \(read.callPrefix)\(namespace).\(storage.memberName).value { \(construction.callPrefix)\(storage.construction) }")
            lines.append("    }")
            return lines
        }

        var lines = [
            "    \(provider.isolation.declarationPrefix)\(access)static var \(memberName): \(displayName(for: injectableKey)) {"
        ]
        lines += interjectionGuardLines(point: "`\(point)`")
        if storage.scope == nil {
            lines.append("        return \(namespace).\(storage.memberName)")
        } else {
            lines.append("        return \(namespace).\(storage.memberName).value { \(storage.construction) }")
        }
        lines.append("    }")
        return lines
    }

    /// What *reading* a kept instance costs, given what *building* it costs.
    ///
    /// Not the same thing, and the difference is the box. A construction that
    /// merely throws still goes through ``ZerkAsyncBox``, because a `static let`
    /// cannot hold a failure and re-attempt it — so reading it is `async throws`
    /// where building it was only `throws`. A construction with no effects at
    /// all keeps its synchronous storage and reads for free.
    static func keptReadEffects(_ building: ProviderEffects) -> ProviderEffects {
        building == .none
            ? .none
            : ProviderEffects(isAsync: true, isThrowing: building.isThrowing)
    }

    /// Where a `sending` return would go.
    ///
    /// `sending` would let a freshly constructed value leave the domain it was
    /// built in without its type having to be `Sendable`, which is the whole
    /// "it just works" story for cross-domain injection. It is **not emitted
    /// yet**, because making it sound requires changes that cannot be validated
    /// without compiling:
    ///
    /// - `sending` is not expressible on a property, so every isolated
    ///   argument-free provider would have to switch from a `var`-shaped member
    ///   to a function-shaped one — a visible API change that also reshapes the
    ///   interjection requirement.
    /// - the resolving variant delegates to the explicit variant, which takes
    ///   caller-supplied parameters and therefore cannot return `sending`. The
    ///   chain only holds if those parameters are themselves `sending`, which
    ///   constrains callers of the explicit variant.
    ///
    /// Emitting it speculatively across every isolated provider risks breaking
    /// the build everywhere at once, so the eligibility is computed and
    /// recorded here and the annotation is left off until the compile harness
    /// can confirm the exact shape. Until then, a value crossing a domain needs
    /// its key to be `Sendable` — which for `actor` and protocol-keyed
    /// injectables it usually already is.
    ///
    /// Deliberately uncalled today. `returnClause` is where it would be called
    /// from; keep the two signatures in step.
    func isSendingEligible(provider: ProviderResolution,
                           parameters: [ParameterRecord],
                           classification: ProviderClassification) -> Bool {
        parameters.isEmpty
            && !provider.isShared
            && provider.isolation.isGlobalActor
            && classification.sharedDependencies.isEmpty
    }

    /// Two values claiming the same key **and name**.
    ///
    /// Values are matched by that pair, so neither can win: the matcher demands
    /// a unique match and finding two silently resolves nothing, leaving the
    /// parameter to the caller. The property form is worse still — two identical
    /// `static var`s land in one `extension Zerk<Key>` and the *generated* file
    /// fails with `invalid redeclaration`, in a file nobody wrote.
    ///
    /// Providers have had this check since collisions were possible; values had
    /// never had one. Grouped by key and name together, so the same value under
    /// two keys, or two values of one key under different names, both stay legal
    /// — those are the normal cases.
    private func duplicateValueDiagnostics() -> [CodegenDiagnostic] {
        var byIdentity: [String: [InjectableValueRecord]] = [:]
        for value in values {
            byIdentity[value.matchIdentity, default: []].append(value)
        }

        var diagnostics: [CodegenDiagnostic] = []
        for (_, group) in byIdentity.sorted(by: { $0.key < $1.key }) {
            // One record per key of the same declaration is not a collision;
            // distinct source positions are what make it one.
            let declarations = group.sorted { $0.location < $1.location }
            guard let first = declarations.first else {
                continue
            }
            // Same name, same key, different `#if` clauses is one value with a
            // definition per configuration — the whole point of writing the
            // `#if` — so only declarations a single build can both see clash.
            for duplicate in declarations.dropFirst()
            where duplicate.location != first.location
                && !CompilationCondition.areExclusive(duplicate.condition, first.condition) {
                diagnostics.append(CodegenDiagnostic(
                    severity: .error,
                    message: "'\(duplicate.name)' is declared as a '\(duplicate.typeName)' value more than once (also at \(first.location.filePath):\(first.location.line)). Values are matched by name as well as type, so two of one name under one key can never be told apart. Rename one, or register it under a different key.",
                    location: duplicate.location
                ))
            }
        }
        return diagnostics
    }

    /// What to do about a member-name collision, which differs by what collided:
    /// a provider is named after its type or its factory, a value after its own
    /// declaration, and neither remedy makes sense for the other.
    private static func collisionRemedy(involvesValue: Bool) -> String {
        involvesValue
            ? "Rename the @InjectableValue, or register it under a different key."
            : "Rename the type, or give the provider a distinct @InjectableProviding function name."
    }

    /// Re-indents a value body so a multi-statement one lines up inside the
    /// generated accessor. Relative indentation is left as written.
    private static func indented(_ body: String, by indent: String) -> [String] {
        body.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : indent + $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - Referenced values

    /// How a `.referenced` value reads its source.
    ///
    /// A member of a type is reached through that type. A *top-level*
    /// declaration cannot be named directly from inside `extension Zerk<Key>`:
    /// the bare name resolves to the generated member itself, which compiles
    /// but recurses forever (the compiler only warns, "attempting to access
    /// within its own getter"). Routing it through a file-scope thunk fixes it,
    /// because file scope has no `Self` for the name to bind to.
    private func referenceRead(for value: InjectableValueRecord) -> String {
        guard let path = value.enclosingTypePath else {
            return "_$zerk_ref_\(value.name)()"
        }
        return "\(path).\(value.name)"
    }

    /// The private forwarding function a **global** `@Injectable` declaration is
    /// called through.
    ///
    /// Inside `extension Zerk<Key>` an unqualified name resolves to the member
    /// being defined, so a member named after its own declaration would call
    /// itself. Forwarding through a file-scope function that was declared
    /// *outside* the extension is what breaks the cycle.
    private func declarationThunkLines(for resolution: ProviderResolution) -> [String] {
        guard case .explicit(let provider) = resolution.provider,
              case .declaration(let reference, let isProperty, let thunk?) = provider.kind else {
            return []
        }
        let generics = resolution.memberGenericParameters
        let genericClause = generics.isEmpty ? "" : "<\(generics.joined(separator: ", "))>"
        let signature = parameterClause(parameters: provider.parameters, defaults: [:])
        let arguments = builderArguments(provider.parameters, useParameterNames: true, defaults: [:])
        let call = isProperty ? reference : "\(reference)(\(arguments))"
        let prefix = provider.isolation.declarationPrefix
        let returns = provider.returnTypeName ?? displayName(for: resolution.injectableKey)
        // The thunk calls the declaration directly, so it needs the declaration's
        // requirements as much as the member does — and it has no `Injectable`
        // to re-derive any of them from, not being inside the extension.
        let constraints = provider.genericConstraints
        let whereClause = constraints.isEmpty
            ? ""
            : " where \(constraints.joined(separator: ", "))"
        return [
            "\(prefix)private func \(thunk)\(genericClause)\(signature)\(provider.effects.declarationSuffix) -> \(returns)\(whereClause) { \(provider.effects.callPrefix)\(call) }"
        ]
    }

    /// The mirror of `referenceRead` for assignment.
    private func referenceWrite(for value: InjectableValueRecord, from expression: String) -> String {
        guard let path = value.enclosingTypePath else {
            return "_$zerk_set_\(value.name)(\(expression))"
        }
        return "\(path).\(value.name) = \(expression)"
    }

    /// File-scope accessors for a top-level referenced value.
    ///
    /// They carry the value's isolation for the same reason generated members
    /// do — a nonisolated thunk cannot read `@MainActor` state — and they spell
    /// `nonisolated` **explicitly**, exactly as a member does.
    ///
    /// Leaving it off is not the same thing. Under
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` an unannotated global
    /// function *is* `@MainActor`, so an omitted `nonisolated` silently flips
    /// the thunk into the ambient domain and the nonisolated member that calls
    /// it stops compiling. Everything Zerk writes is pinned; the settings file
    /// governs how Zerk reads source, never what it emits.
    private func referenceThunkLines(for value: InjectableValueRecord) -> [String] {
        guard value.enclosingTypePath == nil else {
            return []
        }
        let prefix = value.isolation.declarationPrefix
        var lines = [
            "\(prefix)private func _$zerk_ref_\(value.name)()\(value.effects.declarationSuffix) -> \(value.typeName) { \(value.effects.callPrefix)\(value.name) }"
        ]
        if value.isSettable {
            lines.append(
                "\(prefix)private func _$zerk_set_\(value.name)(_ newValue: \(value.typeName)) { \(value.name) = newValue }"
            )
        }
        return lines
    }

    /// The generated member's return type: always the injectable key, so a type
    /// registered as `@Injectable<Storing>` returns `Storing` rather than its
    /// concrete type.
    ///
    /// The unused parameters are deliberate. They mirror `isSendingEligible`'s
    /// signature because this is the seam where a `sending` return would be
    /// applied — the body becomes a choice between `key` and `sending \(key)`,
    /// and both call sites already thread through exactly the arguments that
    /// decision needs. Dropping them would not simplify anything; it would move
    /// the work to whoever finishes `sending`.
    private func returnClause(for provider: ProviderResolution,
                              key: String,
                              parameters: [ParameterRecord],
                              classification: ProviderClassification) -> String {
        key
    }

    /// The primaries a key needs an `inject()` for: one per configuration.
    ///
    /// Normally exactly one, and then this is just `primaryResolutions[key]`. A
    /// key gets several only when mutually exclusive registrations each won
    /// their own configuration — a `#if DEBUG` / `#else` swap — and then each
    /// needs its own `inject()`, because they build different things.
    ///
    /// What they may *not* differ in is the contract: everything that resolves
    /// the key through a default argument spells one call, emitted once, with
    /// one set of effects and one parameter list. If the branches disagree about
    /// those, that single call site would be wrong in one configuration — so it
    /// is refused here rather than emitted and left to fail in the branch nobody
    /// built today.
    private func injectVariants(for injectableKey: String,
                                diagnostics: inout [CodegenDiagnostic]) -> [ProviderResolution] {
        guard let representative = primaryResolutions[injectableKey] else {
            return []
        }
        let variants = primaryVariants[injectableKey] ?? [representative]
        guard variants.count > 1 else {
            return variants
        }

        let expected = wrapperPlan(for: representative)
        var accepted = [representative]

        for variant in variants.dropFirst() {
            let plan = wrapperPlan(for: variant)
            let mismatch = Self.contractMismatch(
                between: (representative, expected),
                and: (variant, plan)
            )
            guard let mismatch else {
                accepted.append(variant)
                continue
            }
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: "'\(variant.typeName)' and '\(representative.typeName)' both resolve '\(displayName(for: injectableKey))', in different branches of one #if, but they \(mismatch). Everything that injects this key resolves it through a single 'Zerk<\(displayName(for: injectableKey))>.inject()' call, emitted once for every configuration, so the branches have to agree on what that call costs. Make them match, or give the branches separate keys.",
                location: variant.provider.location
            ))
        }

        return accepted
    }

    /// How two configurations' primaries differ in what a caller must do to
    /// resolve them, or `nil` when they are interchangeable.
    ///
    /// Only the *observable* half is compared. What each one builds, how it is
    /// named, and whether it is kept are exactly what the branches are there to
    /// vary; the effects, the isolation, and the arguments left for the caller
    /// are what the single emitted call site depends on.
    private static func contractMismatch(
        between representative: (ProviderResolution, WrapperPlan),
        and variant: (ProviderResolution, WrapperPlan)
    ) -> String? {
        if representative.1.effects != variant.1.effects {
            return "resolve with different effects (\(Self.effectsDescription(representative.1.effects)) versus \(Self.effectsDescription(variant.1.effects)))"
        }
        if representative.0.isolation.actorName != variant.0.isolation.actorName {
            return "resolve in different isolation domains (\(Self.isolationDescription(representative.0.isolation)) versus \(Self.isolationDescription(variant.0.isolation)))"
        }
        let left = representative.1.parameters.map { "\($0.label ?? $0.name): \($0.typeName)" }
        let right = variant.1.parameters.map { "\($0.label ?? $0.name): \($0.typeName)" }
        if left != right {
            return "leave different arguments to the caller (\(Self.parameterList(left)) versus \(Self.parameterList(right)))"
        }
        return nil
    }

    private static func parameterList(_ parameters: [String]) -> String {
        parameters.isEmpty ? "none" : parameters.joined(separator: ", ")
    }

    /// How a diagnostic names what resolving costs, as a developer would write
    /// it at the call site.
    private static func effectsDescription(_ effects: ProviderEffects) -> String {
        let suffix = effects.declarationSuffix.trimmingCharacters(in: .whitespaces)
        return suffix.isEmpty ? "neither async nor throwing" : suffix
    }

    private static func isolationDescription(_ isolation: ProviderIsolation) -> String {
        isolation.actorName.map { "@\($0)" } ?? "nonisolated"
    }

    /// Emits `inject()`, the entry point every other generated member and every
    /// `@Injected` property calls.
    private func injectLines(for provider: ProviderResolution,
                             injectableKey: String,
                             classification: ProviderClassification,
                             diagnostics: inout [CodegenDiagnostic]) -> [String] {
        let plan = wrapperPlan(for: provider)
        let memberName = memberName(for: provider)
        let isolation = provider.isolation
        let generics = genericClauses(for: provider, injectableKey: injectableKey)
        // A kept instance's member is a `var` reading its storage, whatever
        // shape its provider had — unless building it carries effects, in which
        // case it is a function that awaits the box.
        let memberIsCallable = provider.isShared
            ? plan.effects != .none
            : (provider.memberIsGeneric ||
               !provider.provider.parameters.isEmpty ||
               provider.provider.effects.isAsync ||
               provider.provider.effects.isThrowing)

        let accessPrefix = exportedAccessPrefix(for: provider, injectableKey: injectableKey)
        if provider.isExported, accessPrefix.isEmpty {
            diagnostics.append(inertPublicDiagnostic(
                injectableKey: injectableKey,
                plural: true,
                location: provider.provider.location
            ))
        }

        let returns = returnClause(
            for: provider,
            key: displayName(for: injectableKey),
            parameters: plan.parameters,
            classification: classification
        )

        var lines: [String] = []
        if plan.parameters.isEmpty {
            // Nothing bubbles up, so the member can resolve everything itself:
            // call it bare and let its defaults (or, when the member split, its
            // resolving variant) do the work. `plan.effects` and the resolving
            // variant's effects agree here, because a defaulted dependency is
            // effect-free by construction.
            lines.append("    \(isolation.declarationPrefix)\(accessPrefix)static func inject\(generics.parameters)()\(plan.effects.declarationSuffix) -> \(returns)\(generics.whereClause) {")
            if memberIsCallable {
                if isOverloaded(memberName, in: injectableKey) {
                    // Sibling providers share this name and are told apart by
                    // their parameters — but each one's parameters are fully
                    // defaulted, so a bare call matches every overload at once.
                    // Naming the arguments is what makes the call resolve; they
                    // are the same expressions the defaults hold.
                    lines.append("        \(provider.provider.effects.callPrefix)\(memberName)(\(memberCallArguments(for: provider, using: plan.argumentExpressions)))")
                } else {
                    lines.append("        \(plan.effects.callPrefix)\(memberName)()")
                }
            } else {
                lines.append("        \(memberName)")
            }
            lines.append("    }")
        } else {
            lines.append("    \(isolation.declarationPrefix)\(accessPrefix)static func inject\(generics.parameters)\(parameterClause(parameters: plan.parameters, defaults: [:]))\(plan.effects.declarationSuffix) -> \(returns)\(generics.whereClause) {")
            lines.append("        \(provider.provider.effects.callPrefix)\(memberName)(\(memberCallArguments(for: provider, using: plan.argumentExpressions)))")
            lines.append("    }")
        }
        return lines
    }

    /// Re-declares the `@Injected` and `@InjectedDynamically` macros inside the
    /// generated file, one overload per distinct `inject()` signature, so a
    /// property can forward arguments through the attribute.
    ///
    /// Every form has to appear here, including the ones that carry no forwarded
    /// arguments and could in principle be left to `Zerk`'s own declarations.
    /// Swift's name lookup stops at the first scope that declares the name at
    /// all, so one module-local declaration shadows *all* of that name's
    /// overloads: a form omitted here does not fall through to `Zerk`'s, it
    /// stops existing in every target the plugin runs in.
    ///
    /// That applies across the two names independently — `Injected` shadows only
    /// `Injected` — but both are declared here anyway, since a module that
    /// declares injectables will have uses of each.
    ///
    /// The roles must not cross: every `Injected` overload is a peer and every
    /// `InjectedDynamically` one an accessor. Mixing roles under a single name
    /// crashes SILGen — see `Sources/Zerk/Macros/InjectedMacro.swift`.
    private func generatedInjectedMacroDeclarations(for signatures: [String]) -> [String] {
        var lines = [
            [
                "@attached(peer, names: prefixed(_$zerk_injection_))",
                "macro Injected() = #externalMacro(module: \"ZerkMacros\", type: \"InjectedMacro\")"
            ],
            // Generic over the key, so one declaration serves every one of them —
            // unlike the argument-forwarding overloads, whose labels differ per
            // provider.
            [
                "@attached(peer, names: prefixed(_$zerk_injection_))",
                "macro Injected<T>() = #externalMacro(module: \"ZerkMacros\", type: \"InjectedMacro\")"
            ],
            [
                "@attached(peer, names: prefixed(_$zerk_injection_))",
                "macro Injected<T>(_ keyPath: KeyPath<Zerk<T>.Type, T>) = #externalMacro(module: \"ZerkMacros\", type: \"InjectedMacro\")"
            ],
            [
                "@attached(accessor)",
                "macro InjectedDynamically() = #externalMacro(module: \"ZerkMacros\", type: \"InjectedDynamicallyMacro\")"
            ],
            [
                "@attached(accessor)",
                "macro InjectedDynamically<T>() = #externalMacro(module: \"ZerkMacros\", type: \"InjectedDynamicallyMacro\")"
            ],
            [
                "@attached(accessor)",
                "macro InjectedDynamically<T>(_ keyPath: KeyPath<Zerk<T>.Type, T>) = #externalMacro(module: \"ZerkMacros\", type: \"InjectedDynamicallyMacro\")"
            ]
        ]

        for signature in signatures where !signature.isEmpty {
            lines.append(
                [
                    "@attached(peer, names: prefixed(_$zerk_injection_))",
                    "macro Injected\(signature) = #externalMacro(module: \"ZerkMacros\", type: \"InjectedMacro\")"
                ]
            )
            lines.append(
                [
                    "@attached(accessor)",
                    "macro InjectedDynamically\(signature) = #externalMacro(module: \"ZerkMacros\", type: \"InjectedDynamicallyMacro\")"
                ]
            )
        }

        return lines
            .joined(separator: [""])
            .map { $0 }
    }

    /// Emits per-type extensions containing overloads of members with
    /// `@injected` parameters: each marked parameter is omitted from the
    /// overload and filled via the resolved `Zerk<Key>` member; unmarked
    /// parameters pass through unchanged. Effects of resolved chains merge
    /// into the overload (an async chain yields an async overload), and a
    /// dependency in another isolation domain merges in as `async` too.
    private func markedMemberLines(diagnostics: inout [CodegenDiagnostic]) -> [String] {
        guard !markedMembers.isEmpty else {
            return []
        }

        var lines: [String] = []
        /// Overload signature -> the conditions it has already been emitted
        /// under, so a clash is decided by what a single build sees.
        var emittedOverloads: [String: [CompilationCondition]] = [:]

        // Globals group under `nil`, which has no ordering of its own — sorted
        // by the empty string so they come first, deterministically.
        let grouped = Dictionary(grouping: markedMembers, by: \.typeName)
        for typeName in grouped.keys.sorted(by: { ($0 ?? "") < ($1 ?? "") }) {
            var memberLines: [String] = []
            // The extension names the type, so it is guarded by whatever every
            // member of it shares — the type's own `#if` when it has one.
            let sharedCondition = CompilationCondition.commonPrefix(of: grouped[typeName]!.map(\.condition))

            for record in grouped[typeName]! {
                var argumentExpressions: [String] = []
                var overloadParameterParts: [String] = []
                var requests: [BubbleResolver.Request] = []
                var dependencyCalls: [String: (prefix: String, dependency: ProviderResolution, typeName: String, label: String?)] = [:]
                var effects = record.effects
                var failed = false

                // The member's own parameters, indexed for the bubbling step. An
                // @injected parameter is resolved rather than passed in, so it
                // cannot feed anything and is excluded.
                let ownParameters = Dictionary(
                    record.parameters
                        .filter { !$0.isMarked }
                        .map { ($0.parameter.resolutionIdentity, $0.parameter) },
                    uniquingKeysWith: { first, _ in first }
                )

                for markedParameter in record.parameters {
                    let core = markedParameter.parameter

                    guard markedParameter.isMarked else {
                        let label = core.label ?? "_"
                        var part = label == core.name
                            ? "\(label): \(core.typeName)"
                            : "\(label) \(core.name): \(core.typeName)"
                        if let defaultText = markedParameter.defaultText {
                            part += " = \(defaultText)"
                        }
                        overloadParameterParts.append(part)
                        argumentExpressions.append(overloadArgument(label: core.label, expression: core.name))
                        continue
                    }

                    if let value = classifier.injectableValue(matching: core) {
                        let hops = value.isolation.requiresHop(callingFrom: record.isolation.dependencyCallContext)
                        let callEffects = value.effects.merged(
                            with: ProviderEffects(isAsync: hops, isThrowing: false))
                        effects = effects.merged(with: callEffects)
                        argumentExpressions.append(
                            overloadArgument(
                                label: core.label,
                                expression: "\(callEffects.callPrefix)\(value.resolutionExpression)"
                            )
                        )
                        continue
                    }

                    if let unique = primaryResolutions[core] {
                        let plan = wrapperPlan(for: unique)
                        let hops = unique.isolation.requiresHop(callingFrom: record.isolation.dependencyCallContext)
                        let callEffects = plan.effects
                            .merged(with: ProviderEffects(isAsync: hops, isThrowing: false))
                        effects = effects.merged(with: callEffects)

                        // Deferred: what each dependency is called with depends
                        // on how *every* dependency's requirements fold together.
                        requests.append(BubbleResolver.Request(
                            sourceName: core.name,
                            requirements: plan.parameters
                        ))
                        dependencyCalls[core.name] = (callEffects.callPrefix, unique, core.typeName, core.label)
                        argumentExpressions.append("\u{0}\(core.name)")
                        continue
                    }

                    diagnostics.append(CodegenDiagnostic(
                        severity: .error,
                        message: "@injected parameter '\(core.name)': '\(core.typeKey)' is not injectable in this module. Declare it @Injectable, or remove @injected.",
                        location: record.location
                    ))
                    failed = true
                    break
                }

                if failed {
                    continue
                }

                let bubble = BubbleResolver.resolve(requests, ownExternals: ownParameters)

                for collision in bubble.collisions {
                    diagnostics.append(CodegenDiagnostic(
                        severity: .error,
                        message: "Resolving @injected parameter '\(collision.dependencyName)' needs '\(collision.requirement.name): \(collision.requirement.typeName)', which collides with this member's own '\(collision.own.name)' parameter. Mark it @injectable to feed the same value to both.",
                        location: collision.own.location ?? record.location
                    ))
                }
                if !bubble.collisions.isEmpty {
                    continue
                }

                // Bubbled parameters go after the member's own, in the order
                // their sources appear.
                overloadParameterParts += bubble.parameters.map { parameter in
                    let label = parameter.label ?? "_"
                    return label == parameter.name
                        ? "\(label): \(parameter.typeName)"
                        : "\(label) \(parameter.name): \(parameter.typeName)"
                }

                argumentExpressions = argumentExpressions.map { expression in
                    guard expression.hasPrefix("\u{0}") else {
                        return expression
                    }
                    let source = String(expression.dropFirst())
                    let call = dependencyCalls[source]!
                    let arguments = bubble.arguments[source] ?? []
                    let expression = call.dependency.provider.resolutionExpression(arguments: arguments)
                        ?? (arguments.isEmpty
                            ? "Zerk<\(call.typeName)>.inject()"
                            : "Zerk<\(call.typeName)>.inject(\(arguments.joined(separator: ", ")))")
                    let resolved = "\(call.prefix)\(expression)"
                    return overloadArgument(label: call.label, expression: resolved)
                }

                let accessPrefix = record.isPublic ? "public " : ""
                let isolationPrefix = record.isolation.declarationPrefix
                let signature = "(\(overloadParameterParts.joined(separator: ", ")))"
                let callArguments = argumentExpressions.joined(separator: ", ")

                let overloadKey: String
                let declarationLines: [String]

                switch record.kind {
                case .initializer:
                    let keyword = record.typeKind == .classKind ? "convenience init" : "init"
                    overloadKey = "\(typeName ?? "").init\(signature)"
                    declarationLines = [
                        "    \(isolationPrefix)\(accessPrefix)\(keyword)\(signature)\(effects.declarationSuffix) {",
                        "        \(record.effects.callPrefix)self.init(\(callArguments))",
                        "    }"
                    ]
                case .method(let name, let isStatic, let returnType):
                    let staticPrefix = isStatic ? "static " : ""
                    let returnSuffix = returnType.map { " -> \($0)" } ?? ""
                    overloadKey = "\(typeName ?? "").\(staticPrefix)\(name)\(signature)"
                    declarationLines = [
                        "    \(isolationPrefix)\(accessPrefix)\(staticPrefix)func \(name)\(signature)\(effects.declarationSuffix)\(returnSuffix) {",
                        "        \(record.effects.callPrefix)\(name)(\(callArguments))",
                        "    }"
                    ]
                case .globalFunction(let name, let returnType):
                    // No enclosing type, so the overload is a file-scope
                    // function: no `extension` wrapper and no indent.
                    let returnSuffix = returnType.map { " -> \($0)" } ?? ""
                    overloadKey = "func \(name)\(signature)"
                    declarationLines = [
                        "\(isolationPrefix)\(accessPrefix)func \(name)\(signature)\(effects.declarationSuffix)\(returnSuffix) {",
                        "    \(record.effects.callPrefix)\(name)(\(callArguments))",
                        "}"
                    ]
                }

                // Keyed on exclusivity, not on the guard's *text*: two records
                // under `#if DEBUG` and `#if os(macOS)` have different text and
                // are both compiled on a macOS debug build, so comparing text
                // would let a real redeclaration through — and replace a clear
                // Zerk error with the compiler's.
                let clash = emittedOverloads[overloadKey]?.contains {
                    !CompilationCondition.areExclusive($0, record.condition)
                } ?? false
                emittedOverloads[overloadKey, default: []].append(record.condition)
                if clash {
                    diagnostics.append(CodegenDiagnostic(
                        severity: .error,
                        message: "Two @injected \(typeName.map { "members of '\($0)'" } ?? "global functions") generate the same overload \(overloadKey). Differentiate the remaining parameters.",
                        location: record.location
                    ))
                    continue
                }

                memberLines += Self.guarded(declarationLines,
                                            by: record.condition.dropping(prefix: sharedCondition))
                memberLines.append("")
            }

            if !memberLines.isEmpty {
                var block: [String] = []
                if let typeName {
                    block.append("extension \(typeName) {")
                    block.append(contentsOf: memberLines.dropLast())
                    block.append("}")
                } else {
                    block.append(contentsOf: memberLines.dropLast())
                }
                lines += Self.guarded(block, by: sharedCondition)
                lines.append("")
            }
        }

        return lines
    }

    /// One argument of a generated call, with its label restored when it has
    /// one.
    private func overloadArgument(label: String?, expression: String) -> String {
        label.map { "\($0): \(expression)" } ?? expression
    }

    /// Detects circular dependencies in the resolution graph up front, so the
    /// classifier's recursion guard never degrades silently. Edges mirror the
    /// classifier's resolution rules: injectable values shadow providers, and
    /// an edge exists only where the dependency resolves through `inject()`.
    ///
    /// Non-primary providers contribute no edges. They are never resolved on
    /// anyone's behalf, so a cycle through one is not a cycle Zerk can walk into
    /// — the caller has to name that member itself.
    /// `@Injected` uses, grouped by the type that declares them.
    ///
    /// Only uses inside a type participate: a property at file scope, or in a
    /// view that nothing injects, is not a node in this graph and cannot be
    /// part of a cycle in it.
    private var eagerInjectedUses: [String: [InjectedUseRecord]] {
        Dictionary(
            grouping: injectedUses.filter {
                $0.macroName == "@Injected" && $0.enclosingTypeName != nil
            },
            by: { $0.enclosingTypeName! }
        )
    }

    /// Whether this key's provider reaches its dependencies through an
    /// `@Injected` property, which is what makes the lazy remedy applicable.
    private func hasEagerInjectedProperty(_ key: String) -> Bool {
        guard let typeName = primaryResolutions[key]?.typeName else {
            return false
        }
        return eagerInjectedUses[typeName]?.isEmpty == false
    }

    private func cycleDiagnostics() -> [CodegenDiagnostic] {
        let classifier = self.classifier

        var edges: [String: [String]] = [:]
        for (key, resolution) in primaryResolutions.entries {
            for parameter in resolution.provider.parameters {
                if classifier.injectableValue(matching: parameter) != nil {
                    continue
                }
                // The edge names the *resolved* key, not the parameter's own
                // spelling: nodes come from the registration keys, so a generic
                // registration is a shape and a parameter naming one of its
                // specializations would point at a node that does not exist.
                if let dependency = primaryResolutions[parameter] {
                    edges[key, default: []].append(dependency.injectableKey)
                }
            }

            // `@Injected` properties are edges too, and they are the ones that
            // used to be missed: not being provider parameters, they left no
            // trace in the graph, so a cycle running through them built cleanly
            // and then overflowed the stack on the first resolution.
            //
            // `@InjectedDynamically` is deliberately absent. Its accessor
            // resolves per read rather than at construction, so it does not
            // close a cycle — it is the remedy this diagnostic points at.
            for use in eagerInjectedUses[resolution.typeName] ?? [] {
                if let dependency = primaryResolutions[use.typeKey, shape: use.typeKeyShape] {
                    edges[key, default: []].append(dependency.injectableKey)
                }
            }
        }

        var diagnostics: [CodegenDiagnostic] = []
        var reportedCycles = Set<String>()
        var finished = Set<String>()

        func visit(_ node: String, path: [String]) {
            if let startIndex = path.firstIndex(of: node) {
                let cycle = Array(path[startIndex...]) + [node]
                let canonical = cycle.dropLast().sorted().joined(separator: "|")
                if reportedCycles.insert(canonical).inserted,
                   let location = primaryResolutions[node]?.provider.location {
                    diagnostics.append(CodegenDiagnostic(
                        severity: .error,
                        // Spelled as the developer would write it: a generic
                        // key's node is a shape (`Cache<#0>`), which is Zerk's
                        // own notation and appears nowhere in their source.
                        message: "Circular dependency detected: \(cycle.map { displayName(for: $0) }.joined(separator: " -> ")). Break the cycle by removing one dependency."
                            + (cycle.contains(where: hasEagerInjectedProperty)
                               ? " One of these resolves the next through an @Injected property, which is read while the instance is being built — @InjectedDynamically resolves on each access instead, which breaks the cycle."
                               : ""),
                        location: location
                    ))
                }
                return
            }
            if finished.contains(node) {
                return
            }
            for next in edges[node] ?? [] {
                visit(next, path: path + [node])
            }
            finished.insert(node)
        }

        for node in edges.keys.sorted() {
            visit(node, path: [])
        }

        return diagnostics
    }

    /// The generated factory's name: whatever the provider stated, or — for an
    /// initializer, which states nothing by default — its type, lowercased.
    private func memberName(for resolution: ProviderResolution) -> String {
        resolution.memberName
    }

    /// Whether more than one provider for this key generates a member of this
    /// name — i.e. whether the name is an overload set rather than a single
    /// member. Two of a type's initializers are the usual way this happens.
    private func isOverloaded(_ name: String, in injectableKey: String) -> Bool {
        resolutions.filter {
            $0.injectableKey == injectableKey && memberName(for: $0) == name
        }
        .count > 1
    }

    /// Every signature the member(s) generated for one provider will occupy.
    ///
    /// Two of a type's initializers are both named after that type, so their
    /// members share a name and are told apart by their parameters — exactly as
    /// the initializers themselves are. Sharing a name is therefore not a
    /// collision; sharing a name *and* a parameter list is.
    ///
    /// A provider yields two signatures when its dependencies split it, since
    /// both variants carry the same name. A property-shaped member is keyed as
    /// taking no parameters, which is conservative: Swift will not accept a
    /// `var` alongside an argument-free `func` of the same name either.
    private func memberSignatureKeys(for provider: ProviderResolution, name: String) -> [String] {
        guard !provider.isSingleton else {
            return ["\(name)()"]
        }

        let parameters = provider.provider.parameters
        let effects = provider.provider.effects
        guard !parameters.isEmpty || effects.isAsync || effects.isThrowing else {
            return ["\(name)()"]
        }

        var keys = ["\(name)\(protocolParameterClause(parameters))"]

        let classification = classifier.classify(provider)
        if classification.requiresSplit {
            keys.append("\(name)\(protocolParameterClause(classification.resolvingVariantParameters))")
        }
        return keys
    }

    /// Renders a parameter list, attaching a default value to each parameter
    /// the classifier put in the **S** partition.
    private func parameterClause(parameters: [ParameterRecord], defaults: [String: String]) -> String {
        let parts = parameters.map { parameter in
            let label = renderedLabel(for: parameter)
            if let defaultValue = defaults[parameter.name] {
                if label == parameter.name {
                    return "\(label): \(parameter.typeName) = \(defaultValue)"
                }
                return "\(label) \(parameter.name): \(parameter.typeName) = \(defaultValue)"
            }
            if label == parameter.name {
                return "\(label): \(parameter.typeName)"
            }
            return "\(label) \(parameter.name): \(parameter.typeName)"
        }
        // The empty case handled directly. Building "( )" and rewriting " )"
        // globally would also rewrite it anywhere inside a parameter's type or
        // default expression.
        return parts.isEmpty ? "()" : "(\(parts.joined(separator: ", ")))"
    }

    /// Forwards a parameter to an inner call by name, keeping its label.
    private func callArgument(for parameter: ParameterRecord) -> String {
        if let label = parameter.label {
            return "\(label): \(parameter.name)"
        }
        return parameter.name
    }

    /// The label as written, or `_` for a parameter declared without one.
    private func renderedLabel(for parameter: ParameterRecord) -> String {
        parameter.label ?? "_"
    }

    // MARK: - Interjection

    /// Emits the interjection guard that opens every generated member body:
    /// if `Zerk<Key>` conforms to the matching `Interjecting<Key>` protocol and
    /// the mirrored member returns a value, that value is used instead of the
    /// real provider. `callArguments` is `nil` for property-shaped members and
    /// the (possibly empty) argument list for function-shaped members.
    /// The lookup at the top of every generated member.
    ///
    /// No type annotation: `_$interjected(for:)` returns `T?` concretely, so
    /// there is no generic parameter for Swift to solve as the fallback's type.
    /// No `#if DEBUG` either — that lives inside the helper, which is
    /// `@inlinable`, so a release build deletes the branch *and* the key-path
    /// formation. Confirmed in optimized SIL: the member reduces to its
    /// construction alone.
    /// The guard for one provider's member, which differs by what its key can
    /// declare a point on.
    ///
    /// - A key that is a type gets a point in its own namespace, and the guard
    ///   names it.
    /// - A **generic** key cannot — `extension Zerk<Cache<E>>.Interjection` is
    ///   "cannot find type 'E' in scope" — but a generated marker protocol
    ///   scopes one to exactly its specializations, so the guard is the same.
    /// - A **parameterized existential** key can do neither: an existential
    ///   conforms to nothing, so there is no marker to constrain by. It falls
    ///   back to the by-key lookup, which needs no point — `#Interject<any
    ///   Boxable<Int, String>>` still reaches it.
    private func interjectionGuardLines(for provider: ProviderResolution,
                                        point: String) -> [String] {
        guard !provider.isParameterizedExistential else {
            return [
                "        if let interjected = _$interjected() {",
                "            return interjected",
                "        }"
            ]
        }
        return interjectionGuardLines(point: "`\(point)`")
    }

    /// Where this provider's point is declared, or `nil` when it can have none.
    private func pointScope(for provider: ProviderResolution,
                            injectableKey: String) -> InterjectionPoint.Scope? {
        if provider.isParameterizedExistential {
            return nil
        }
        guard provider.keyIsGeneric else {
            return .key(injectableKey)
        }
        // A generic key is the registering type itself, so that type is what
        // carries the marker.
        //
        // The type's name goes in **verbatim**, inside a raw identifier, rather
        // than through `sanitizedIdentifier`. Sanitizing collapses `Outer.Bar`
        // and `OuterBar` onto one name, which for two markers would mean one
        // protocol claiming both families and points leaking between them.
        // Backticks the type itself carried are dropped, since the name is being
        // put inside a pair of them.
        return .marker(protocolName: "_$ZerkInjectable_\(provider.typeName.filter { $0 != "`" })",
                       baseType: provider.typeName)
    }

    private func interjectionGuardLines(point: String,
                                        indent: String = "        ") -> [String] {
        [
            "\(indent)if let interjected = _$interjected(for: \\.\(point)) {",
            "\(indent)    return interjected",
            "\(indent)}"
        ]
    }

    /// The platforms that have parameterized existentials (SE-0346, Swift 5.7).
    ///
    /// visionOS and macCatalyst are listed rather than left to `*` so the
    /// generated line says what it means on every platform Zerk supports.
    static let parameterizedExistentialAvailability =
        "@available(iOS 16.0, macOS 13.0, macCatalyst 16.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)"

    /// What a member for a generic key adds to its declaration: the parameter
    /// list it introduces, and the requirement binding `Injectable` to the key.
    ///
    /// Empty strings for a concrete key, so every emission site interpolates
    /// them unconditionally and concrete output stays byte-identical.
    ///
    /// The constraints written on the *type* — `struct Codec<E: Codable>` — are
    /// deliberately not reproduced. `where Injectable == Codec<E>` re-derives
    /// them from the same-type requirement, and a specialization that violates
    /// one still fails at the call site with the constraint's own message.
    ///
    /// The constraints written on the *provider* are reproduced, because that
    /// argument does not reach them: `init<Z: Numeric>` puts `Z` nowhere in the
    /// return type, so nothing binds it and nothing re-derives it. They are
    /// emitted as `where` requirements, which is what a parameter's inheritance
    /// clause means anyway and composes with the binding already there.
    private func genericClauses(for provider: ProviderResolution,
                                injectableKey: String) -> (parameters: String, whereClause: String) {
        guard provider.memberIsGeneric else {
            return ("", "")
        }
        // Only a generic key needs binding. A concrete one is already bound by
        // the extension header, and the member is an ordinary generic method
        // whose parameters come from its arguments.
        var requirements: [String] = []
        if provider.keyIsGeneric {
            requirements.append("Injectable == \(displayName(for: injectableKey))")
        }
        requirements += provider.provider.genericConstraints

        return (
            "<\(provider.memberGenericParameters.joined(separator: ", "))>",
            requirements.isEmpty ? "" : " where \(requirements.joined(separator: ", "))"
        )
    }

    /// The expression that constructs the real implementation, e.g. `Logger`
    /// for an initializer provider or `LiveUserService.live` for a static one.
    private func builderConstruction(for resolution: ProviderResolution) -> String {
        switch resolution.provider {
        case .explicit(let provider):
            switch provider.kind {
            case .initializer:
                return resolution.typeName
            case .staticFunction(let name):
                return "\(resolution.typeName).\(name)"
            case .declaration(let reference, _, let thunk):
                // The declaration itself, not a member of the key: the key is
                // what it *builds*, and may be a type from another module. A
                // global goes through its thunk, which is what keeps the member
                // from shadowing it.
                return thunk ?? reference
            }
        case .imported(let record):
            // Never reached while imports stay out of `resolutions`: they build
            // nothing here, so no member is emitted for them. Answering with the
            // resolving expression keeps this total rather than fatal.
            return record.callee
        case .implicit:
            return resolution.typeName
        }
    }

    /// Labeled arguments passed to the real builder. Function-shaped members
    /// forward their own parameter names (which carry resolved defaults);
    /// property-shaped members inline the resolved default expressions.
    private func builderArguments(_ parameters: [ParameterRecord],
                                  useParameterNames: Bool,
                                  defaults: [String: String]) -> String {
        parameters.map { parameter in
            let value = useParameterNames ? parameter.name : (defaults[parameter.name] ?? parameter.name)
            if let label = parameter.label {
                return "\(label): \(value)"
            }
            return value
        }
        .joined(separator: ", ")
    }

    /// Labeled arguments forwarded to the mirrored interjection member, using
    /// the enclosing member's parameter names.

    /// The interjection requirement mirroring a generated member: `live`
    /// becomes `interjectedLive`.

    /// `Interjecting` plus the key rendered as an identifier, e.g.
    /// `InterjectingStoring`.

    /// Uppercases the first character only, leaving the rest as written.
    private func upperFirst(_ string: String) -> String {
        guard let first = string.first else {
            return string
        }
        return first.uppercased() + string.dropFirst()
    }

    /// Reduces a type key to characters legal in an identifier, so keys like
    /// `[String]` or `any Storing` can still name a generated protocol or
    /// function.
    private func sanitizedIdentifier(_ key: String) -> String {
        let scalars = key.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == "_"
        }
        return String(String.UnicodeScalarView(scalars))
    }

    /// Emits one `Interjecting<Key>` protocol per injectable key, gathering the
    /// requirements contributed by that key's members. Developers conform
    /// `Zerk<Key>` to these protocols in their test suites to override members.
    ///
    /// Requirements mirror the isolation of the member they stand in for: a
    /// generated member cannot call a requirement that lives in another domain.
    /// What identifies a provider while naming points: its member name and full
    /// parameter shape, which the collision check has already proved unique
    /// within the key.
    private func pointIdentity(for provider: ProviderResolution) -> String {
        InterjectionPointName.text(
            member: memberName(for: provider),
            parameters: provider.provider.parameters.map { "\($0.label ?? "_"): \($0.typeName)" }
        )
    }

    /// Names every provider's interjection point, as short as the key allows.
    ///
    /// Three forms, escalating only when the previous one is ambiguous:
    ///
    /// | members sharing the name | point |
    /// |---|---|
    /// | one | `live` |
    /// | several, distinct labels | `loader(store:)` |
    /// | several, same labels | `loader(store: Disk)` |
    ///
    /// A group escalates as a whole rather than per member, so every overload of
    /// one name is spelled the same way — a mix would be harder to predict than
    /// either form alone.
    ///
    /// Adding an overload can therefore rename an existing point, which turns
    /// interjections naming it into compile errors. That is the intended
    /// outcome: the name really did stop identifying one member.
    private func interjectionPointNames(for providers: [ProviderResolution]) -> [String: String] {
        var names: [String: String] = [:]

        for (member, group) in Dictionary(grouping: providers, by: { memberName(for: $0) }) {
            guard group.count > 1 else {
                names[pointIdentity(for: group[0])] = member
                continue
            }

            let labelForms = group.map { provider in
                InterjectionPointName.selector(
                    member: member,
                    labels: provider.provider.parameters.map { $0.label ?? "_" }
                )
            }
            let labelsSuffice = Set(labelForms).count == group.count

            for (offset, provider) in group.enumerated() {
                names[pointIdentity(for: provider)] = labelsSuffice
                    ? labelForms[offset]
                    : pointIdentity(for: provider)
            }
        }

        return names
    }

    /// Emits each key's `Interjection` namespace — one `Void` property per
    /// generated member, named after that member's signature.
    ///
    /// Kept off `Zerk<Key>` itself: hung there, the point for an argument-free
    /// member would collide with the member, since both would be
    /// `static var live`. In the namespace every member gets one whatever its
    /// shape, and `Zerk<Key>`'s own surface is untouched.
    private func interjectionPointLines(points: [InterjectionPoint]) -> [String] {
        guard !points.isEmpty else {
            return []
        }

        var lines: [String] = []
        let grouped = Dictionary(grouping: points, by: \.scope)

        // Markers first, and each declared once: the protocol and its
        // conformance have to precede the extension constrained by them, and a
        // base type with several generic keys would otherwise conform twice.
        var declaredMarkers = Set<String>()
        for scope in grouped.keys.sorted(by: { Self.scopeOrder($0) < Self.scopeOrder($1) }) {
            guard case .marker(let protocolName, let baseType) = scope,
                  declaredMarkers.insert(protocolName).inserted else {
                continue
            }
            lines += Self.guarded([
                "protocol `\(protocolName)` {}",
                "extension \(baseType): `\(protocolName)` {}"
            ], by: CompilationCondition.commonPrefix(of: grouped[scope]!.map(\.condition)))
            lines.append("")
        }

        for scope in grouped.keys.sorted(by: { Self.scopeOrder($0) < Self.scopeOrder($1) }) {
            // Deduped by name, which already carries the parameters: several
            // providers for one key can share a member name, and each overload
            // needs its own point.
            //
            // A name reached from two `#if` clauses is declared once per clause,
            // under each guard, since the members it stands for are different
            // members. One reachable unconditionally is declared once and
            // unguarded — the widest of its conditions covers the rest, and
            // declaring it twice in one configuration would not compile.
            var conditionsByName: [String: [CompilationCondition]] = [:]
            for point in grouped[scope]! {
                conditionsByName[point.name, default: []].append(point.condition)
            }
            let sharedCondition = CompilationCondition.commonPrefix(of: grouped[scope]!.map(\.condition))

            var block: [String] = []
            switch scope {
            case .key(let key):
                block.append("extension Zerk<\(displayName(for: key))>.Interjection {")
            case .marker(let protocolName, _):
                block.append("extension Zerk.Interjection where Injectable: `\(protocolName)` {")
            }
            for name in conditionsByName.keys.sorted() {
                // Pinned `nonisolated`, and not from the member's isolation: a
                // point is a `Void` marker with no state, and every member has
                // to form a key path to it. Left unannotated it inherits the
                // ambient default, so under `SWIFT_DEFAULT_ACTOR_ISOLATION =
                // MainActor` a *nonisolated* member cannot form the key path at
                // all — "cannot form key path to main actor-isolated property".
                // Nonisolated is reachable from every domain, including an
                // isolated member's.
                let declaration = "    nonisolated var `\(name)`: Void {}"
                let conditions = conditionsByName[name]!.map { $0.dropping(prefix: sharedCondition) }
                guard !conditions.contains(where: \.isUnconditional) else {
                    block.append(declaration)
                    continue
                }
                var emitted = Set<String>()
                for condition in conditions.sorted(by: { $0.sortKey < $1.sortKey })
                where emitted.insert(condition.guardText ?? "").inserted {
                    block += Self.guarded([declaration], by: condition)
                }
            }
            block.append("}")

            lines += Self.guarded(block, by: sharedCondition)
            lines.append("")
        }

        return lines
    }

    /// A stable order for point scopes, so the generated file does not depend on
    /// dictionary iteration.
    static func scopeOrder(_ scope: InterjectionPoint.Scope) -> String {
        switch scope {
        case .key(let key):
            return "0\(key)"
        case .marker(let protocolName, _):
            return "1\(protocolName)"
        }
    }

    /// What makes two interjection requirements the same requirement: the
    /// mirrored member's name together with its parameters.

    /// Whether the spelling has a space or `&` outside any bracket, which is
    /// what makes a trailing `?` ambiguous.
    private func hasTopLevelBreak(_ text: String) -> Bool {
        var depth = 0
        for character in text {
            switch character {
            case "<", "(", "[":
                depth += 1
            case ">", ")", "]":
                depth = max(0, depth - 1)
            case " ", "&":
                if depth == 0 {
                    return true
                }
            default:
                break
            }
        }
        return false
    }

    /// Like `parameterClause`, minus defaults: a protocol requirement cannot
    /// declare them.
    private func protocolParameterClause(_ parameters: [ParameterRecord]) -> String {
        let parts = parameters.map { parameter -> String in
            let label = parameter.label ?? "_"
            if label == parameter.name {
                return "\(label): \(parameter.typeName)"
            }
            return "\(label) \(parameter.name): \(parameter.typeName)"
        }
        return "(\(parts.joined(separator: ", ")))"
    }

    // MARK: - Sendability

    /// One "this singleton is reached from that consumer" pair.
    ///
    /// Equality and hashing deliberately ignore `consumerIsolation`: which
    /// check to emit is decided by the singleton/consumer pair alone, and the
    /// isolation only decorates the generated comment. Including it would emit
    /// near-duplicate checks for a single logical crossing.
    private struct SendabilityCheck: Hashable {
        let shared: SharedDependency
        let consumerTypeName: String
        let consumerIsolation: ProviderIsolation
        /// The `#if` the consuming provider is declared under. The check names
        /// both types, so it belongs in the same configurations.
        var condition: CompilationCondition = .unconditional

        var sharedTypeName: String { shared.typeName }

        /// How the generated comment names what crossed: the attribute, not the
        /// scope. `@Scoped(.session)` and `@Scoped(.checkout)` need the same
        /// conformance for the same reason, and the scope is not part of it.
        var attributeName: String {
            shared.scope == nil ? "@Singleton" : "@Scoped"
        }

        static func == (lhs: SendabilityCheck, rhs: SendabilityCheck) -> Bool {
            lhs.sharedTypeName == rhs.sharedTypeName
                && lhs.consumerTypeName == rhs.consumerTypeName
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(sharedTypeName)
            hasher.combine(consumerTypeName)
        }
    }

    /// Zerk cannot prove `Sendable` from syntax, and does not try. The check
    /// costs nothing when the type already conforms, so it is emitted
    /// unconditionally wherever a singleton crosses an isolation boundary and
    /// the compiler is left to decide — with the failure landing on a line
    /// carrying an explanation rather than deep inside a factory body.
    private func sendabilityCheckLines(_ checks: [SendabilityCheck]) -> [String] {
        let unique = Array(Set(checks)).sorted {
            ($0.sharedTypeName, $0.consumerTypeName) < ($1.sharedTypeName, $1.consumerTypeName)
        }
        guard !unique.isEmpty else {
            return []
        }

        var lines = [
            "private func _$zerk_sendable_conformance_check<T: Sendable>(_: T.Type) {}",
            ""
        ]

        for check in unique {
            let domain = check.consumerIsolation.actorName.map { "'\($0)'-isolated " } ?? ""
            lines += Self.guarded([
                "private func _$zerk_sendable_conformance_check_\(sanitizedIdentifier(check.sharedTypeName))_in_\(sanitizedIdentifier(check.consumerTypeName))() {",
                "    // '\(check.attributeName) \(check.sharedTypeName)' is injected into \(domain)'\(check.consumerTypeName)'.",
                "    // A shared instance that crosses isolation domains must be Sendable.",
                "    _$zerk_sendable_conformance_check(\(check.sharedTypeName).self)",
                "}"
            ], by: check.condition)
            lines.append("")
        }

        return lines
    }

    // MARK: - inject() flattening

    /// Identifies an `inject()` overload by parameter shape, so the generated
    /// `@Injected` macro declarations are emitted once per distinct signature
    /// rather than once per provider.
    private func macroSignatureKey(for parameters: [ParameterRecord],
                                   genericParameters: [String] = []) -> String {
        guard !parameters.isEmpty else {
            return ""
        }
        let parts = parameters.map { parameter in
            let label = parameter.label ?? "_"
            return "\(label): \(parameter.typeName)"
        }
        // A forwarded argument may be typed by one of the member's own generic
        // parameters — `@Injected(1, "a") var box: any Boxable` against
        // `inject<X, Y>(_ x: X, _ y: Y)`. The declaration binds exactly the ones
        // its signature names: binding more is "generic parameter not used in
        // function signature", and binding fewer does not resolve.
        let named = genericParameters.filter { name in
            parameters.contains { $0.mentionedGenericParameters.contains(name) }
        }
        let clause = named.isEmpty ? "" : "<\(named.joined(separator: ", "))>"
        return "\(clause)(\(parts.joined(separator: ", ")))"
    }

    /// Flattens a provider's whole dependency subtree into a single `inject()`
    /// signature: every parameter that cannot be resolved anywhere in the tree
    /// bubbles up, and everything else is inlined as an expression.
    ///
    /// This is deliberately different from the E/S/A classification, which only
    /// looks one level down to decide what a *named member* exposes.
    private func wrapperPlan(for resolution: ProviderResolution,
                             visiting: Set<String> = []) -> WrapperPlan {
        let resolutionKey = "\(resolution.injectableKey)|\(resolution.typeName)"
        if visiting.contains(resolutionKey) {
            return WrapperPlan(
                parameters: resolution.provider.parameters,
                argumentExpressions: resolution.provider.parameters.map(callArgument),
                effects: resolution.provider.effects
            )
        }

        let nextVisiting = visiting.union([resolutionKey])
        let memberIsolation = resolution.isolation
        let classifier = self.classifier

        var ownParameters: [ParameterRecord] = []
        var argumentExpressions: [String] = []
        var effects = resolution.provider.effects
        // Gathered first, resolved together: sharing and disambiguation are
        // decisions about the whole set, not about one dependency at a time.
        var requests: [BubbleResolver.Request] = []
        var dependencyCalls: [String: (prefix: String, dependency: ProviderResolution, typeName: String)] = [:]

        // Explicit mode applies here too. `inject()` flattens the whole subtree,
        // so without this an unmarked parameter would still be resolved behind
        // the caller's back — the exact thing marking asks Zerk not to do.
        let isExplicit = resolution.provider.parameters.contains(where: \.isAutoInjected)

        // Which parameters this provider exposes itself, computed up front: a
        // dependency may bubble a requirement before the parameter that would
        // feed it has been reached. Mirrors the branches of the loop below.
        var ownExternals: [String: ParameterRecord] = [:]
        for parameter in resolution.provider.parameters {
            let staysExternal: Bool
            if isExplicit ? !parameter.isAutoInjected : parameter.isNonInjected {
                staysExternal = true
            } else if classifier.injectableValue(matching: parameter) != nil {
                staysExternal = false
            } else if primaryResolutions[parameter] != nil {
                staysExternal = false
            } else {
                staysExternal = true
            }
            if staysExternal {
                ownExternals[parameter.resolutionIdentity] = parameter
            }
        }

        for parameter in resolution.provider.parameters {
            if isExplicit ? !parameter.isAutoInjected : parameter.isNonInjected {
                ownParameters = mergeParameters(ownParameters, with: [parameter])
                argumentExpressions.append(parameter.name)
                continue
            }

            if let value = classifier.injectableValue(matching: parameter) {
                let hops = value.isolation.requiresHop(callingFrom: memberIsolation)
                // The value's own `async`/`throws` merge with the hop: reading
                // it costs both, and `inject()` has to declare both.
                let callEffects = value.effects.merged(
                    with: ProviderEffects(isAsync: hops, isThrowing: false))

                // A value is read rather than built, so nothing of its own can
                // bubble; the read is the whole expression.
                effects = effects.merged(with: callEffects)
                argumentExpressions.append("\(callEffects.callPrefix)\(value.resolutionExpression)")
                continue
            }

            if let dependency = primaryResolutions[parameter] {
                let dependencyPlan = wrapperPlan(for: dependency, visiting: nextVisiting)
                let hops = dependency.isolation.requiresHop(callingFrom: memberIsolation)
                let callEffects = dependencyPlan.effects
                    .merged(with: ProviderEffects(isAsync: hops, isThrowing: false))
                effects = effects.merged(with: callEffects)

                // Placeholder: the call cannot be written until every
                // dependency's requirements have been folded together.
                requests.append(BubbleResolver.Request(
                    sourceName: parameter.name,
                    requirements: dependencyPlan.parameters
                ))
                // An import resolves through the expression it named; everything else
                // through this module's own inject().
                dependencyCalls[parameter.name] = (callEffects.callPrefix, dependency, parameter.typeName)
                argumentExpressions.append("\u{0}\(parameter.name)")
                continue
            }

            ownParameters = mergeParameters(ownParameters, with: [parameter])
            argumentExpressions.append(parameter.name)
        }

        let bubble = BubbleResolver.resolve(requests, ownExternals: ownExternals)

        // Bubbled parameters go after the provider's own, in the order their
        // sources appear — the same shape the @injected overload uses.
        return WrapperPlan(
            parameters: ownParameters + bubble.parameters,
            argumentExpressions: argumentExpressions.map { expression in
                guard expression.hasPrefix("\u{0}") else {
                    return expression
                }
                let source = String(expression.dropFirst())
                let call = dependencyCalls[source]!
                let arguments = bubble.arguments[source] ?? []
                let resolved = call.dependency.provider.resolutionExpression(arguments: arguments)
                    ?? (arguments.isEmpty
                        ? "Zerk<\(call.typeName)>.inject()"
                        : "Zerk<\(call.typeName)>.inject(\(arguments.joined(separator: ", ")))")
                return "\(call.prefix)\(resolved)"
            },
            // A kept instance is *read*, and reading it costs what the box
            // charges rather than what the construction did. Applied here so
            // every consumer of the plan agrees — `inject()`, a default
            // argument, an `@injected` overload, and the `@Injected` refusal.
            effects: resolution.isShared ? Self.keptReadEffects(effects) : effects,
            collisions: bubble.collisions
        )
    }

    /// Unions parameter lists in order, dropping exact duplicates: two
    /// dependencies may need the same caller-supplied parameter, which must
    /// still appear once in the generated signature.
    private func mergeParameters(_ existing: [ParameterRecord], with newParameters: [ParameterRecord]) -> [ParameterRecord] {
        var merged = existing
        var seen = Set(existing.map(parameterIdentity))

        for parameter in newParameters {
            let identity = parameterIdentity(parameter)
            if seen.insert(identity).inserted {
                merged.append(parameter)
            }
        }

        return merged
    }

    /// Deduplication identity: label, name, and type together. Parameters
    /// agreeing on all three are interchangeable at the call site.
    private func parameterIdentity(_ parameter: ParameterRecord) -> String {
        "\(parameter.label ?? "_")|\(parameter.name)|\(parameter.typeKey)|\(parameter.typeName)"
    }

    /// Pairs a provider's parameters with their resolved expressions,
    /// restoring argument labels.
    private func memberCallArguments(for resolution: ProviderResolution, using expressions: [String]) -> String {
        zip(resolution.provider.parameters, expressions)
            .map { parameter, expression in
                if let label = parameter.label {
                    return "\(label): \(expression)"
                }
                return expression
            }
            .joined(separator: ", ")
    }
}
