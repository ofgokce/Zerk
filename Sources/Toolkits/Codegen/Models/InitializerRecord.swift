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
    let parameters: [ParameterRecord]
    let effects: ProviderEffects
    let location: AttributeLocation
    /// Isolation domain the provider constructs in, resolved from the
    /// declaration, its enclosing type, and the ambient default at collection
    /// time.
    var isolation: ProviderIsolation = .nonisolated
}
