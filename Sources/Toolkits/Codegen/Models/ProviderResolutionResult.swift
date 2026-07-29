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
    let resolutions: [ProviderResolution]
    let diagnostics: [CodegenDiagnostic]
}
