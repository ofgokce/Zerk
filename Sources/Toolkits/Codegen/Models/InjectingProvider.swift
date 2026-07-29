//
//  InjectingProvider.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

/// A declaration explicitly marked `@Providing`, i.e. one the developer chose
/// as the way to build a type.
///
/// Takes precedence over any implicit `InitializerRecord`; the two carry the
/// same information otherwise, differing only in `kind` (initializer vs. named
/// static factory).
struct InjectingProvider {
    let kind: ProviderKind
    let parameters: [ParameterRecord]
    let effects: ProviderEffects
    let location: AttributeLocation
    /// Isolation domain the provider constructs in, resolved from the
    /// declaration, its enclosing type, and the ambient default at collection
    /// time.
    var isolation: ProviderIsolation = .nonisolated
}
