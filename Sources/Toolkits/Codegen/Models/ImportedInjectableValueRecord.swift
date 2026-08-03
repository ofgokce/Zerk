//
//  ImportedInjectableValueRecord.swift
//  Zerk
//

/// An `@ImportedInjectableValue` declaration: a *value* that lives in another
/// module, named well enough for this module's graph to match against.
///
/// Kept apart from ``ImportedInjectableRecord`` because the two are matched
/// differently, which is the whole reason values need their own import. A key
/// import answers for its key; a value is matched by key **and name** together,
/// so a module can import as many values of one type as it likes and each keeps
/// its own identity.
///
/// `name` is the *local* declaration's name — what parameters have to be called
/// to match it — while `expression` names the foreign member. They are usually
/// the same, and deliberately need not be: a module whose parameters spell it
/// differently can rename on import.
struct ImportedInjectableValueRecord {
    /// Canonical key, from the declared type annotation.
    var typeKey: String
    /// The type as written, for emitting.
    let typeName: String
    let name: String
    /// The expression that reads it, e.g. `Zerk<String>.baseURL`. Inlined at
    /// every use site, so it is kept whole rather than reassembled.
    let expression: String
    let isolation: ProviderIsolation
    let location: AttributeLocation
}
