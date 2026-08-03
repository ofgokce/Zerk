//
//  ImportedInjectableRecord.swift
//  Zerk
//

/// An `@ImportedInjectable` declaration: a key that lives in another module,
/// described well enough for this module's graph to resolve against it.
///
/// Zerk resolves within one module, so a foreign key is invisible to it — this
/// is how one is described. The declaration is never called; only its shape is
/// used, plus the expression to resolve through.
struct ImportedInjectableRecord {
    /// Canonical key, from the declared return type.
    var typeKey: String
    /// The return type as written, for emitting.
    let typeName: String
    let parameters: [ParameterRecord]
    let effects: ProviderEffects
    let isolation: ProviderIsolation
    /// The expression that resolves it, without arguments —
    /// `Zerk<Session>.inject` by default, or whatever a written body named.
    let callee: String
    /// Whether the body named a property rather than a call — `Zerk<X>.staging`
    /// takes no parentheses, and adding them would not compile.
    let resolvesAsProperty: Bool
    let location: AttributeLocation
}
