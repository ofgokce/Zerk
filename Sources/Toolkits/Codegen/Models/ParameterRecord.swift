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
    /// `var` so a bubbled requirement can be renamed when its name would repeat.
    var name: String
    var typeKey: String
    let typeName: String
    /// `@autoinjected` — the developer asked Zerk to resolve this one.
    ///
    /// A provider with any marked parameter resolves *only* those; see
    /// `ParameterClassifier`. Left `false` everywhere else, so a provider that
    /// marks nothing keeps the inferred behaviour.
    var isAutoInjected: Bool = false
    /// `@noninjected` — kept out of resolution even where Zerk could satisfy it.
    /// The inverse of `isAutoInjected`, and only consulted while a provider is
    /// inferring; explicit mode already excludes everything unmarked.
    var isNonInjected: Bool = false
    /// `@injectable` — available to satisfy a bubbled requirement of one of this
    /// member's resolved dependencies, so a single parameter serves both.
    var feedsDependencies: Bool = false
    /// Where the parameter was written, so "this one cannot be resolved" points
    /// at the parameter rather than at the declaration. `nil` for parameters
    /// Zerk synthesized itself, which have no source of their own.
    var location: AttributeLocation? = nil

    /// Identity for matching a bubbled requirement to a parameter that can feed
    /// it: name and type, ignoring the label. The requirement's label comes from
    /// the *dependency's* declaration and need not match the member's.
    var resolutionIdentity: String { "\(name)|\(typeKey)" }

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
