//
//  InterjectionRequirement.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

/// One requirement of a generated `Interjecting<Key>` protocol. Each generated
/// injector member (provider or value) contributes exactly one requirement,
/// mirroring the member so developers can override it from their test suites.
struct InterjectionRequirement {
    /// Whether the mirrored member is a property or a function — a
    /// parameterless provider becomes a `static var`, anything else a
    /// `static func`.
    enum Kind {
        case variable
        case function(parameters: [ParameterRecord])
    }

    /// The type inside `Zerk<...>` the member lives on (e.g. `ApiServicing`).
    let zerkArgument: String
    /// The mirrored member name, e.g. `interjectedLogger`.
    let interjectedName: String
    /// The type the member returns; the requirement returns it as Optional.
    let returnTypeName: String
    let kind: Kind
    /// Mirrors the isolation of the member it stands in for. A requirement in
    /// the wrong domain cannot be called from the generated member's body.
    let isolation: ProviderIsolation
}
