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
    var parameters: [ParameterRecord]
    let effects: ProviderEffects
    let location: AttributeLocation
    /// The return type as written, or `nil` for an initializer — which can only
    /// ever produce its own type, so there is nothing to read.
    ///
    /// Only `@Singleton` consults it: shared storage has to be typed, and the
    /// provider's declared return type is the one type the construction
    /// expression is known to produce.
    var returnTypeName: String?
    /// Isolation domain the provider constructs in, resolved from the
    /// declaration, its enclosing type, and the ambient default at collection
    /// time.
    var isolation: ProviderIsolation = .nonisolated
    /// Whether `@InjectableProviding(primary: true)` named this provider as the
    /// one `inject()` calls, among its type's providers for the same key.
    var isPrimary: Bool = false
    /// The factory's *own* generic parameters. See
    /// ``InitializerRecord/genericParameters``.
    var genericParameters: [String] = []
}
