//
//  InitializerRecord.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

/// An initializer Zerk may adopt as a provider implicitly, when the type has
/// exactly one and declares no `@InjectableProviding`.
///
/// Recorded for every initializer, since "exactly one" is only knowable after
/// the whole type has been walked.
struct InitializerRecord {
    var parameters: [ParameterRecord]
    let effects: ProviderEffects
    let location: AttributeLocation
    /// Isolation domain the provider constructs in, resolved from the
    /// declaration, its enclosing type, and the ambient default at collection
    /// time.
    var isolation: ProviderIsolation = .nonisolated
    /// The initializer's *own* generic parameters — `["Z"]` for
    /// `init<Z>(x: X, y: Y, z: Z)` inside `Box<X, Y>`.
    ///
    /// Separate from the type's: the emitted member declares both, but only the
    /// type's can be bound by the return type. Anything the member adds has to
    /// arrive as an argument, since nothing else in the signature mentions it.
    var genericParameters: [String] = []
    /// Requirements on the provider's *own* generic parameters, as written —
    /// `["Z: Numeric"]` for `init<Z: Numeric>`.
    ///
    /// Carried for exactly the reason ``genericParameters`` is separate. The
    /// type's constraints need no recording: `where Injectable == Codec<E>`
    /// re-derives them, because the same-type requirement makes `Codec<E>` be
    /// well-formed. Nothing re-derives these — `Z` appears nowhere in the return
    /// type — so a member that dropped them would call an initializer whose
    /// requirements it does not satisfy, and fail inside the generated file.
    ///
    /// Held as requirement text rather than as an inheritance clause because
    /// that is the form the member emits: a parameter's `: Numeric` is sugar for
    /// a `where` requirement, and the member already has a `where` clause to
    /// join.
    var genericConstraints: [String] = []
}
