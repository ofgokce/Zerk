//
//  ParameterRecord.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

/// One parameter of a provider.
///
/// `typeKey` is the normalized spelling, used to *match* the parameter against
/// a registered injectable; `typeName` is the spelling as written, used when
/// emitting it back out. Keeping both means matching is insensitive to
/// whitespace without the generated code losing the developer's formatting.
struct ParameterRecord: Equatable {
    let label: String?
    let name: String
    var typeKey: String
    let typeName: String
    /// `@autoinjected` — the developer asked Zerk to resolve this one.
    ///
    /// A provider with any marked parameter resolves *only* those; see
    /// `ParameterClassifier`. Left `false` everywhere else, so a provider that
    /// marks nothing keeps the inferred behaviour.
    var isAutoInjected: Bool = false
    /// Where the parameter was written, so "this one cannot be resolved" points
    /// at the parameter rather than at the declaration. `nil` for parameters
    /// Zerk synthesized itself, which have no source of their own.
    var location: AttributeLocation? = nil

    /// Equality ignores the marker and the location: two parameters are
    /// interchangeable at a call site when their label, name and type agree, and
    /// `mergeParameters` dedupes on exactly that.
    static func == (lhs: ParameterRecord, rhs: ParameterRecord) -> Bool {
        lhs.label == rhs.label
            && lhs.name == rhs.name
            && lhs.typeKey == rhs.typeKey
            && lhs.typeName == rhs.typeName
    }
}
