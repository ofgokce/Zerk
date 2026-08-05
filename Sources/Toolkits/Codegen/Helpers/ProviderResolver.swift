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
                            message: "No @InjectableProviding provider found for @Injectable<\(key)> on '\(type.name)'.",
                            location: type.injectableKeys[key]!
                        ))
                    }
                    continue
                }

                // A singleton is one shared instance by definition, so a second
                // way to build it would mean a second instance under the same
                // key — which is the one thing @Singleton promises cannot
                // happen.
                if type.isSingleton, providers.count > 1 {
                    diagnostics.append(CodegenDiagnostic(
                        severity: .error,
                        message: "@Singleton '\(type.name)' declares multiple providers for '\(key)'. A singleton must have exactly one provider per key.",
                        location: providers[1].location
                    ))
                    continue
                }

                typeResolutions += providers.map {
                    resolution(of: type, key: key, provider: .explicit($0))
                }
            }

            if type.isSingleton {
                typeResolutions = validatedSingleton(type, resolutions: typeResolutions, into: &diagnostics)
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
    -> (primaries: [String: ProviderResolution], diagnostics: [CodegenDiagnostic]) {
        var primaries: [String: ProviderResolution] = [:]
        var diagnostics: [CodegenDiagnostic] = []

        let grouped = Dictionary(grouping: resolutions, by: \.injectableKey)

        for key in grouped.keys.sorted() {
            let candidates = grouped[key]!.sorted { $0.provider.location < $1.provider.location }

            guard let typeName = electType(for: key, among: candidates, aliases: aliases, into: &diagnostics) else {
                continue
            }
            guard let winner = electProvider(
                for: key,
                of: typeName,
                among: candidates.filter({ $0.typeName == typeName }),
                into: &diagnostics
            ) else {
                continue
            }

            primaries[key] = winner
        }

        return (primaries, diagnostics)
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

    /// Enforces the two rules that only make sense once a `@Singleton`'s keys
    /// are all resolved, and drops the type's resolutions when either is broken
    /// — the generator has no shared instance to emit in that case.
    ///
    /// Both follow from the same fact: a singleton is *one* instance, stored
    /// once and read through every key it claims.
    ///
    /// 1. **One provider across all keys.** Per-key uniqueness is checked at
    ///    collection; this catches the other shape, where each key names a
    ///    different factory. One instance cannot be built two ways.
    /// 2. **A multi-key singleton's provider returns the concrete type.** The
    ///    shared storage is typed as the provider's return type, so a factory
    ///    declaring one of the keys produces storage the *other* keys cannot be
    ///    served from. An initializer is exempt: it always yields the type
    ///    itself.
    func validatedSingleton(_ type: TypeRecord,
                            resolutions: [ProviderResolution],
                            into diagnostics: inout [CodegenDiagnostic]) -> [ProviderResolution] {
        guard let first = resolutions.first else {
            return resolutions
        }

        // Same declaration, not same record: a factory bound to two keys yields
        // one record per attribute, and those share a location.
        if let mismatch = resolutions.first(where: { $0.provider.location != first.provider.location }) {
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: "@Singleton '\(type.name)' resolves to different providers for '\(first.injectableKey)' (\(Self.providerDescription(first.provider))) and '\(mismatch.injectableKey)' (\(Self.providerDescription(mismatch.provider))). A singleton has one instance, so it must have one provider across all its keys.",
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
                message: "@Singleton '\(type.name)' is injectable under \(keyCount) keys, so its provider must return '\(type.name)' rather than '\(returnTypeName)'. One instance is shared by every key, and storage typed '\(returnTypeName)' cannot serve the others.",
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
