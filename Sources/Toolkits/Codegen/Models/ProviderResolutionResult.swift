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

    /// Every primary elected for a key — one per configuration, when `#if`
    /// clauses gave the key a different winner in each.
    ///
    /// Normally a single entry, and the same resolution ``primaryResolutions``
    /// holds. It has more only where mutually exclusive registrations each won
    /// their own configuration, and then each needs its own `inject()` under its
    /// own guard. Everything that resolves *through* `inject()` keeps reading
    /// ``primaryResolutions``, because the call it emits is the same text in
    /// every configuration.
    var primaryVariants: [String: [ProviderResolution]] = [:]

    let diagnostics: [CodegenDiagnostic]
}
