//
//  ProviderResolver.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

/// Decides *which* providers satisfy each `@Injectable` key, and which single
/// one of them backs `inject()`.
///
/// This stage is purely about provider selection. Isolation, effects, and
/// parameter resolution are all downstream — see `ParameterClassifier` and
/// `GeneratorOutputBuilder`.
struct ProviderResolver {

    let types: [TypeRecord]

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
            for key in type.injectableKeys.keys.sorted() {
                let providers = explicitProviders(of: type, for: key)

                guard !providers.isEmpty else {
                    if type.initializers.count == 1 {
                        resolutions.append(
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

                resolutions += providers.map {
                    resolution(of: type, key: key, provider: .explicit($0))
                }
            }
        }

        let election = Self.electPrimaries(among: resolutions)

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
    static func electPrimaries(among resolutions: [ProviderResolution])
    -> (primaries: [String: ProviderResolution], diagnostics: [CodegenDiagnostic]) {
        var primaries: [String: ProviderResolution] = [:]
        var diagnostics: [CodegenDiagnostic] = []

        let grouped = Dictionary(grouping: resolutions, by: \.injectableKey)

        for key in grouped.keys.sorted() {
            let candidates = grouped[key]!.sorted { $0.provider.location < $1.provider.location }

            guard let typeName = electType(for: key, among: candidates, into: &diagnostics) else {
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

    func resolution(of type: TypeRecord,
                    key: String,
                    provider: ProviderChoice) -> ProviderResolution {
        ProviderResolution(
            typeName: type.name,
            injectableKey: key,
            provider: provider,
            isTypePrimary: type.primaryKeys[key] != nil,
            isShared: type.sharedKeys[key] != nil,
            isSingleton: type.isSingleton
        )
    }

    /// Which type wins the key. Unanimous when only one type claims it.
    static func electType(for key: String,
                          among candidates: [ProviderResolution],
                          into diagnostics: inout [CodegenDiagnostic]) -> String? {
        let typeNames = uniqued(candidates.map(\.typeName))
        if typeNames.count == 1 {
            return typeNames[0]
        }

        let claimants = uniqued(candidates.filter(\.isTypePrimary).map(\.typeName))

        guard let first = claimants.first else {
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: "Multiple types are injectable under '\(key)' (\(typeNames.joined(separator: ", "))) and none is primary. Mark one with @Injectable(primary: true).",
                location: candidates[0].provider.location
            ))
            return nil
        }

        if claimants.count > 1 {
            let second = candidates.first { $0.typeName == claimants[1] && $0.isTypePrimary }
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: "Multiple primary injectables found for '\(key)' (\(claimants.joined(separator: ", "))). Only one type can be primary for a key.",
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

    /// Order-preserving deduplication, so diagnostics list competing types in
    /// source order rather than in a `Set`'s.
    static func uniqued(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }
}
