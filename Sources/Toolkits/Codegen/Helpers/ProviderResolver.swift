//
//  ProviderResolver.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

/// Decides *which* provider satisfies each `@Injectable` key, and reports the
/// cases where that choice is ambiguous or impossible.
///
/// This stage is purely about provider selection. Isolation, effects, and
/// parameter resolution are all downstream — see `ParameterClassifier` and
/// `GeneratorOutputBuilder`.
struct ProviderResolver {

    let types: [TypeRecord]

    /// Resolves every `@Injectable` key on every type, in this precedence
    /// order:
    ///
    /// 1. a `@Providing<Key>` provider matching that exact key;
    /// 2. an untyped `@Providing` provider, which serves every key on the type;
    /// 3. the type's sole initializer, used implicitly.
    ///
    /// A type with several initializers and no `@Providing` is an error rather
    /// than a guess. Duplicate providers, and duplicate `@Primary` claims on one
    /// key, are reported here too — `GeneratorOutputBuilder` relies on each key
    /// having at most one winner.
    func resolve() -> ProviderResolutionResult {
        var resolutions: [ProviderResolution] = []
        var diagnostics: [CodegenDiagnostic] = []

        for type in types {
            if type.defaultProviders.count > 1 {
                diagnostics.append(CodegenDiagnostic(
                    severity: .error,
                    message: "Multiple non-generic @Providing providers found on '\(type.name)'.",
                    location: type.defaultProviders[1].location
                ))
            }

            for (key, providers) in type.typedProviders where providers.count > 1 {
                diagnostics.append(CodegenDiagnostic(
                    severity: .error,
                    message: "Multiple @Providing<\(key)> providers found on '\(type.name)'.",
                    location: providers[1].location
                ))
            }

            for (key, location) in type.injectableKeys {
                if let typed = type.typedProviders[key]?.first {
                    resolutions.append(ProviderResolution(
                        typeName: type.name,
                        injectableKey: key,
                        provider: .explicit(typed),
                        isPrimary: type.primaryKeys[key] != nil,
                        isShared: type.sharedKeys[key] != nil,
                        isSingleton: type.isSingleton
                    ))
                    continue
                }

                if let provider = type.defaultProviders.first {
                    resolutions.append(ProviderResolution(
                        typeName: type.name,
                        injectableKey: key,
                        provider: .explicit(provider),
                        isPrimary: type.primaryKeys[key] != nil,
                        isShared: type.sharedKeys[key] != nil,
                        isSingleton: type.isSingleton
                    ))
                    continue
                }

                if type.initializers.count == 1 {
                    resolutions.append(ProviderResolution(
                        typeName: type.name,
                        injectableKey: key,
                        provider: .implicit(type.initializers[0]),
                        isPrimary: type.primaryKeys[key] != nil,
                        isShared: type.sharedKeys[key] != nil,
                        isSingleton: type.isSingleton
                    ))
                    continue
                }

                diagnostics.append(CodegenDiagnostic(
                    severity: .error,
                    message: "No @Providing provider found for @Injectable<\(key)> on '\(type.name)'.",
                    location: location
                ))
            }
        }

        let grouped = Dictionary(grouping: resolutions, by: \.injectableKey)
        for (key, providers) in grouped {
            let primaryProviders = providers.filter(\.isPrimary)
            if primaryProviders.count > 1 {
                diagnostics.append(CodegenDiagnostic(
                    severity: .error,
                    message: "Multiple @Primary injectables found for '\(key)'. Only one primary implementation is allowed.",
                    location: primaryProviders[1].provider.location
                ))
            }
        }

        return ProviderResolutionResult(resolutions: resolutions, diagnostics: diagnostics)
    }
}
