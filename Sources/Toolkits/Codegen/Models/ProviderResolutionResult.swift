//
//  ProviderResolutionResult.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

/// Everything `ProviderResolver` produced. Diagnostics travel alongside the
/// resolutions instead of being thrown, so resolution failures for one key do
/// not hide problems with another.
struct ProviderResolutionResult {
    /// Every (key, provider) pair in the module. One generated member each.
    let resolutions: [ProviderResolution]

    /// The single provider that backs `Zerk<Key>.inject()`, per key.
    ///
    /// Also what every *implicit* resolution uses: a dependency parameter, an
    /// `@injected` argument, and an `@Injected` property all resolve through
    /// `inject()`, so they follow this map rather than guessing among the
    /// members. A key is absent only when resolving it produced a diagnostic.
    let primaryResolutions: [String: ProviderResolution]

    let diagnostics: [CodegenDiagnostic]
}
