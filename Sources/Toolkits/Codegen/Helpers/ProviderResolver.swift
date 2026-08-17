//
//  ProviderResolver.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

import SharedToolkit

/// Decides *which* providers satisfy each `@Injectable` key, and which single
/// one of them backs `inject()`.
///
/// This stage is purely about provider selection. Isolation, effects, and
/// parameter resolution are all downstream — see `ParameterClassifier` and
/// `GeneratorOutputBuilder`.
struct ProviderResolver {

    let types: [TypeRecord]
    /// Keys merged by `@ZerkAlias` / `#ZerkAlias`. Records already arrive
    /// rewritten to representatives, so this is consulted only to *explain* a
    /// collision the developer did not literally write.
    var aliases: KeyAliases = .empty
    /// The spelling each key was written as. For diagnostics only: keys match
    /// with `any` stripped, and a developer who wrote `@Injectable<any Boxable>`
    /// should not be told about `Boxable`.
    var keyDisplayNames: [String: String] = [:]

    /// Collects every provider for every key, then elects one primary per key.
    ///
    /// A key's providers are the union of the `@InjectableProviding<Key>`
    /// declarations naming it and the untyped `@InjectableProviding`
    /// declarations, which serve every key on their type. Only when a type
    /// declares no provider at all does its sole initializer stand in; declaring
    /// one provider is a deliberate choice that a bare initializer must not
    /// silently join.
    ///
    /// Several providers per key is the normal case, not an error — each becomes
    /// its own named member. What must be unambiguous is `inject()`, and
    /// `electPrimaries` is where that is settled.
    func resolve() -> ProviderResolutionResult {
        var resolutions: [ProviderResolution] = []
        var diagnostics: [CodegenDiagnostic] = []

        for type in types {
            var typeResolutions: [ProviderResolution] = []

            for key in type.injectableKeys.keys.sorted() {
                let providers = explicitProviders(of: type, for: key)

                guard !providers.isEmpty else {
                    if type.initializers.count == 1 {
                        typeResolutions.append(
                            resolution(of: type, key: key, provider: .implicit(type.initializers[0]))
                        )
                    } else {
                        diagnostics.append(CodegenDiagnostic(
                            severity: .error,
                            message: "No @InjectableProviding provider found for @Injectable<\(key)> on '\(type.name)'."
                                + (type.initializerInferenceRefusal.map { " \($0) Declare an initializer, or mark a factory @InjectableProviding." } ?? ""),
                            location: type.injectableKeys[key]!
                        ))
                    }
                    continue
                }

                // A kept instance is one instance by definition, so a second way
                // to build it is a contradiction: both members would read the
                // *same* storage, so asking for one factory would hand back what
                // the other built. Half the rule — the other half, that every key
                // names the same provider, needs all the keys resolved and lives
                // in `validatedShared`.
                if type.isShared, providers.count > 1 {
                    diagnostics.append(CodegenDiagnostic(
                        severity: .error,
                        message: "\(type.sharingAttributeName) '\(type.name)' declares multiple providers for '\(key)'. The instance is stored once and read through every key it claims, so it has exactly one provider in total — not one per key. Keep whichever builds it.",
                        location: providers[1].location
                    ))
                    continue
                }

                typeResolutions += providers.map {
                    resolution(of: type, key: key, provider: .explicit($0))
                }
            }

            if type.isShared {
                typeResolutions = validatedShared(type, resolutions: typeResolutions, into: &diagnostics)
            }

            resolutions += typeResolutions
        }

        // A written key erases the type's parameters, so each provider has to
        // recover them from its own arguments. One that cannot would emit
        // `generic parameter 'Y' is not used in function signature`, so it is
        // dropped here rather than left to fail inside the generated file.
        resolutions = resolutions.filter { resolution in
            let unbound = Self.unboundParameters(of: resolution)
            guard !unbound.fromKey.isEmpty || !unbound.fromProvider.isEmpty else {
                return true
            }
            // Two different mistakes with two different fixes, so they are
            // worded — and reported — separately.
            if !unbound.fromKey.isEmpty {
                diagnostics.append(CodegenDiagnostic(
                    severity: .error,
                    message: GenericRefusal.unboundKeyParameters(
                        on: resolution.typeName,
                        key: keyDisplayNames[resolution.injectableKey] ?? resolution.injectableKey,
                        provider: resolution.provider.declarationDescription,
                        parameters: unbound.fromKey
                    ),
                    location: resolution.provider.location
                ))
            }
            if !unbound.fromProvider.isEmpty {
                diagnostics.append(CodegenDiagnostic(
                    severity: .error,
                    message: GenericRefusal.unboundProviderParameters(
                        on: resolution.typeName,
                        provider: resolution.provider.declarationDescription,
                        parameters: unbound.fromProvider
                    ),
                    location: resolution.provider.location
                ))
            }
            return false
        }

        let election = Self.electPrimaries(among: resolutions, aliases: aliases)

        return ProviderResolutionResult(
            resolutions: resolutions,
            primaryResolutions: election.primaries,
            primaryVariants: election.variants,
            diagnostics: diagnostics + election.diagnostics
        )
    }
}

extension ProviderResolver {

    /// Narrows each key's providers down to the one `inject()` calls.
    ///
    /// Two rounds, because there are two ways to be ambiguous. First the *type*:
    /// several types injectable under one key need one of them marked
    /// `@Injectable(primary: true)`. Then, within the type that won, the
    /// *provider*: several providers for that key need one marked
    /// `@InjectableProviding(primary: true)`.
    ///
    /// The second round runs only for the winning type. A type that lost the key
    /// never supplies `inject()`, so its providers have nothing to disambiguate
    /// — they are simply named members, and demanding a primary among them would
    /// be an annotation with no effect.
    ///
    /// A pure function of the resolutions, so it is `static`: nothing here needs
    /// the `TypeRecord`s the rest of the resolver works from.
    static func electPrimaries(among resolutions: [ProviderResolution],
                               aliases: KeyAliases = .empty)
    -> (primaries: [String: ProviderResolution],
        variants: [String: [ProviderResolution]],
        diagnostics: [CodegenDiagnostic]) {
        var primaries: [String: ProviderResolution] = [:]
        var variants: [String: [ProviderResolution]] = [:]
        var diagnostics: [CodegenDiagnostic] = []

        let grouped = Dictionary(grouping: resolutions, by: \.injectableKey)

        for key in grouped.keys.sorted() {
            let candidates = grouped[key]!.sorted { $0.provider.location < $1.provider.location }
            var winners: [ProviderResolution] = []

            // One election per configuration rather than one per key: a
            // `#if DEBUG` / `#else` pair registers the same key twice, but no
            // build sees both, so asking them to agree on a primary would be
            // asking them to resolve an ambiguity that does not exist.
            for group in coexisting(among: candidates) {
                guard let typeName = electType(for: key, among: group, aliases: aliases, into: &diagnostics) else {
                    continue
                }
                guard let winner = electProvider(
                    for: key,
                    of: typeName,
                    among: group.filter({ $0.typeName == typeName }),
                    into: &diagnostics
                ) else {
                    continue
                }
                if !winners.contains(where: { $0.provider.location == winner.provider.location }) {
                    winners.append(winner)
                }
            }

            guard let representative = winners.first else {
                continue
            }
            // Every configuration's winner is kept, because each needs its own
            // `inject()` under its own guard. The first is the representative:
            // everything that resolves *through* `inject()` — a dependency
            // parameter, an `@Injected` property — spells the same call
            // whichever configuration is built, so it needs one answer, and the
            // emitter refuses variants that would not agree on what that call
            // costs.
            primaries[key] = representative
            variants[key] = winners
        }

        return (primaries, variants, deduplicated(diagnostics))
    }

    /// The candidate sets that can be present together, one per configuration
    /// worth electing for.
    ///
    /// Every group is **pairwise** compatible: no two of its members are
    /// mutually exclusive. Taking "everything compatible with one pivot" is not
    /// enough and was the bug — an unconditional candidate is compatible with
    /// *both* clauses of a `#if`/`#else`, so pivoting on it produced a group
    /// containing both branches, a configuration no build ever has. A fallback
    /// registration plus a per-configuration override then collided with itself.
    ///
    /// Split on a *condition* the candidates disagree about rather than by
    /// enumerating cliques: taking one that somebody asserts and somebody else
    /// requires to have failed, and splitting on whether it holds, removes
    /// exactly one disagreement — and a candidate indifferent to it belongs to
    /// both halves. Recursion terminates because neither half can dispute that
    /// condition again, and there are finitely many.
    ///
    /// Splitting on the *condition* rather than on the `#if` block is what makes
    /// this the same question ``CompilationCondition/areExclusive(_:_:)``
    /// answers. Partitioning by block was narrower, and the gap was not
    /// academic: a DEBUG/Release swap written over two blocks was reported as
    /// two rival providers, and marking one of them primary — which is what the
    /// diagnostic asks for — produced a file with an `inject()` in the Debug
    /// configuration and none in the Release one, called unconditionally from
    /// every consumer.
    ///
    /// Clauses of one `#if` are covered by the same rule rather than by a second
    /// one: an `#elseif` denies every condition before it and an `#else` denies
    /// all of them, so the clauses of a block disagree textually about the
    /// block's own conditions.
    static func coexisting(among candidates: [ProviderResolution]) -> [[ProviderResolution]] {
        guard let condition = disputedCondition(among: candidates) else {
            return [candidates]
        }

        var groups: [[ProviderResolution]] = []
        var seen = Set<String>()

        // Where it holds, then where it fails. A candidate that neither asserts
        // nor denies it is in both, being present whichever way the build goes.
        let halves = [
            candidates.filter { !$0.condition.denies(condition) },
            candidates.filter { !$0.condition.asserts(condition) }
        ]

        for half in halves {
            for group in coexisting(among: half) {
                let identity = group.map { String(describing: $0.provider.location) }.joined(separator: "|")
                if seen.insert(identity).inserted {
                    groups.append(group)
                }
            }
        }

        return groups
    }

    /// A condition one candidate asserts and another requires to have failed, or
    /// `nil` when every candidate can coexist with every other.
    ///
    /// Sorted, so which one is settled first — and therefore the order the
    /// groups come out in — does not depend on how the candidates were
    /// enumerated.
    static func disputedCondition(among candidates: [ProviderResolution]) -> String? {
        var asserted: Set<String> = []
        var denied: Set<String> = []
        for candidate in candidates {
            let mentioned = candidate.condition.mentionedConditions
            asserted.formUnion(mentioned.asserted)
            denied.formUnion(mentioned.denied)
        }
        return asserted.intersection(denied).sorted().first
    }

    /// Drops repeats, since one mistake reachable from two configurations is
    /// still one mistake.
    static func deduplicated(_ diagnostics: [CodegenDiagnostic]) -> [CodegenDiagnostic] {
        var seen = Set<String>()
        return diagnostics.filter {
            seen.insert("\($0.location)|\($0.severity)|\($0.message)").inserted
        }
    }
}

private extension ProviderResolver {

    /// Every explicitly marked provider serving one key on one type, in source
    /// order.
    ///
    /// Typed and untyped providers *combine* here rather than the typed one
    /// shadowing the untyped one: both were written deliberately, and both
    /// become members.
    func explicitProviders(of type: TypeRecord, for key: String) -> [InjectingProvider] {
        ((type.typedProviders[key] ?? []) + type.defaultProviders)
            .sorted { $0.location < $1.location }
    }

    /// Enforces the two rules that only make sense once a shared type's keys are
    /// all resolved, and drops the type's resolutions when either is broken —
    /// the generator has no instance to emit in that case.
    ///
    /// Both follow from the same fact, and it is the fact `@Singleton` and
    /// `@Scoped` have in common: the instance is built *once*, stored once, and
    /// read through every key the type claims. How long it is kept for does not
    /// enter into either rule, which is why one function serves both.
    ///
    /// 1. **One provider across all keys.** Per-key uniqueness is checked as
    ///    each key resolves, above; this catches the other shape, where every
    ///    key names one provider but not the *same* one. Together the two mean
    ///    exactly one provider — one instance cannot be built two ways.
    /// 2. **A multi-key type's provider returns the concrete type.** The storage
    ///    is typed as the provider's return type, so a factory declaring one of
    ///    the keys produces storage the *other* keys cannot be served from. An
    ///    initializer is exempt: it always yields the type itself.
    func validatedShared(_ type: TypeRecord,
                         resolutions: [ProviderResolution],
                         into diagnostics: inout [CodegenDiagnostic]) -> [ProviderResolution] {
        guard let first = resolutions.first else {
            return resolutions
        }
        let attribute = type.sharingAttributeName

        // Same declaration, not same record: a factory bound to two keys yields
        // one record per attribute, and those share a location.
        if let mismatch = resolutions.first(where: { $0.provider.location != first.provider.location }) {
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: "\(attribute) '\(type.name)' resolves to different providers for '\(first.injectableKey)' (\(Self.providerDescription(first.provider))) and '\(mismatch.injectableKey)' (\(Self.providerDescription(mismatch.provider))). There is one instance, so it must have one provider across all its keys.",
                location: mismatch.provider.location
            ))
            return []
        }

        let keyCount = Set(resolutions.map(\.injectableKey)).count
        if keyCount > 1,
           let returnTypeName = first.provider.returnTypeName,
           returnTypeName != type.name {
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: "\(attribute) '\(type.name)' is injectable under \(keyCount) keys, so its provider must return '\(type.name)' rather than '\(returnTypeName)'. One instance serves every key, and storage typed '\(returnTypeName)' cannot serve the others.",
                location: first.provider.location
            ))
            return []
        }

        return resolutions
    }

    /// The generic parameters this resolution's member declares but nothing in
    /// its signature could infer, or `nil` when every one is reachable.
    ///
    /// Swift's own rule, said at the declaration instead of at the generated
    /// line: a generic parameter must appear in the signature. Two things can
    /// put it there.
    ///
    /// - The **return type**, but only when the key carries the type's
    ///   parameters — `-> Cache<E>`. A key that erases them (`-> any Boxable`)
    ///   or never had them (`-> Box`) mentions none.
    /// - An **argument**, which is the only route for anything the provider
    ///   declares itself: `init<Z>(z: Z)` puts `Z` there, `init<Z>()` does not.
    static func unboundParameters(of resolution: ProviderResolution)
    -> (fromKey: [String], fromProvider: [String]) {
        guard resolution.memberIsGeneric else {
            return ([], [])
        }
        let boundByReturnType = resolution.keyIsGeneric
            ? Set(resolution.genericParameters)
            : Set<String>()
        let boundByArguments = Set(
            resolution.provider.parameters.flatMap(\.mentionedGenericParameters))
        func isUnbound(_ name: String) -> Bool {
            !boundByReturnType.contains(name) && !boundByArguments.contains(name)
        }
        return (
            fromKey: resolution.genericParameters.filter(isUnbound),
            fromProvider: resolution.provider.genericParameters.filter(isUnbound)
        )
    }

    /// How a provider is named in a diagnostic: a factory by its own name, an
    /// initializer as `init`.
    static func providerDescription(_ provider: ProviderChoice) -> String {
        provider.declarationDescription.map { "'\($0)'" } ?? "init"
    }

    func resolution(of type: TypeRecord,
                    key: String,
                    provider: ProviderChoice) -> ProviderResolution {
        ProviderResolution(
            typeName: type.name,
            injectableKey: key,
            provider: provider,
            isTypePrimary: type.primaryKeys[key] != nil,
            isExported: type.exportedKeys[key] != nil,
            isSingleton: type.isSingleton,
            scope: type.scope,
            condition: type.condition,
            genericParameters: type.genericParameters,
            isParameterizedExistential: type.parameterizedKeys[key] != nil
        )
    }

    /// Which type wins the key. Unanimous when only one type claims it.
    static func electType(for key: String,
                          among candidates: [ProviderResolution],
                          aliases: KeyAliases,
                          into diagnostics: inout [CodegenDiagnostic]) -> String? {
        let typeNames = uniqued(candidates.map(\.typeName))
        if typeNames.count == 1 {
            return typeNames[0]
        }

        let claimants = uniqued(candidates.filter(\.isTypePrimary).map(\.typeName))

        guard let first = claimants.first else {
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: "Multiple types are injectable under '\(key)' (\(typeNames.joined(separator: ", "))) and none is primary.\(Self.aliasSentence(for: key, aliases: aliases)) Mark one with @Injectable(primary: true).",
                location: candidates[0].provider.location
            ))
            return nil
        }

        if claimants.count > 1 {
            let second = candidates.first { $0.typeName == claimants[1] && $0.isTypePrimary }
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: "Multiple primary injectables found for '\(key)' (\(claimants.joined(separator: ", "))). Only one type can be primary for a key.\(Self.aliasSentence(for: key, aliases: aliases))",
                location: second?.provider.location ?? candidates[0].provider.location
            ))
            return nil
        }

        return first
    }

    /// Which of the winning type's providers wins the key.
    static func electProvider(for key: String,
                              of typeName: String,
                              among candidates: [ProviderResolution],
                              into diagnostics: inout [CodegenDiagnostic]) -> ProviderResolution? {
        if candidates.count == 1 {
            return candidates[0]
        }

        let claimants = candidates.filter(\.isProviderPrimary)

        guard let first = claimants.first else {
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: "'\(typeName)' declares multiple providers for '\(key)' and none is primary. Mark one with @InjectableProviding(primary: true).",
                location: candidates[1].provider.location
            ))
            return nil
        }

        if claimants.count > 1 {
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: "'\(typeName)' declares multiple primary providers for '\(key)'. Only one provider can be primary for a key.",
                location: claimants[1].provider.location
            ))
            return nil
        }

        return first
    }

    /// Names the alias that merged two keys, so a collision the developer did
    /// not literally write still explains itself.
    ///
    /// Without it the message reports a key that appears nowhere in their
    /// source — the representative Zerk elected — and the merge looks arbitrary.
    static func aliasSentence(for key: String, aliases: KeyAliases) -> String {
        let others = aliases.aliases(of: key)
        guard !others.isEmpty else {
            return ""
        }
        let list = others.map { "'\($0)'" }.joined(separator: ", ")
        return " '\(key)' and \(list) are the same type (registered via @ZerkAlias), so those declarations claim one key."
    }

    /// Order-preserving deduplication, so diagnostics list competing types in
    /// source order rather than in a `Set`'s.
    static func uniqued(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }
}
