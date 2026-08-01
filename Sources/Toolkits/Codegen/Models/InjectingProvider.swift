//
//  InjectingProvider.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

/// A declaration explicitly marked `@InjectableProviding`, i.e. one the
/// developer chose as a way to build a type.
///
/// Suppresses any implicit `InitializerRecord`; the two carry the same
/// information otherwise, differing only in `kind` (initializer vs. named
/// static factory).
///
/// One record per *attribute*, not per declaration. A factory bound to two keys
/// with `@InjectableProviding<A>(primary: true) @InjectableProviding<B>` yields
/// two records, because `isPrimary` is a claim about one key.
struct InjectingProvider {
    let kind: ProviderKind
    let parameters: [ParameterRecord]
    let effects: ProviderEffects
    let location: AttributeLocation
    /// Isolation domain the provider constructs in, resolved from the
    /// declaration, its enclosing type, and the ambient default at collection
    /// time.
    var isolation: ProviderIsolation = .nonisolated
    /// Whether `@InjectableProviding(primary: true)` named this provider as the
    /// one `inject()` calls, among its type's providers for the same key.
    var isPrimary: Bool = false
}
