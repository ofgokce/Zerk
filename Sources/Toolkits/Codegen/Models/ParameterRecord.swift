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
    /// The type's ``KeyShape``, read from its syntax — `Cache<#0>` for
    /// `Cache<String>`, `nil` for anything no generic registration could match.
    ///
    /// Carried rather than derived at the lookup, because deriving it would mean
    /// taking `typeKey` apart, and a canonical key only looks decomposable.
    var typeKeyShape: String? = nil
    /// The enclosing declarations' generic parameters this parameter's type
    /// mentions — `["E"]` for `serializer: Serializer<E>` inside `Cache<E>`.
    ///
    /// Empty for every parameter of a non-generic type, which is why the field
    /// costs nothing today. What it buys is the distinction the `typeKey` alone
    /// cannot make: `Serializer<E>` is a *family* of keys, resolvable only
    /// against a provider registered for the same family, while `Logger` is one
    /// key resolvable by exact match.
    var mentionedGenericParameters: [String] = []
    /// Whether the type *is* an enclosing generic parameter (`item: E`) rather
    /// than a type mentioning one.
    ///
    /// Kept apart from ``mentionedGenericParameters`` because the two want
    /// opposite answers: a mention can be resolved once matching understands
    /// families, and a bare parameter never can — no declaration registers `E`,
    /// and matching it by name would silently bind a module type that happens to
    /// be spelled the same.
    var isBareGenericParameter: Bool = false

    /// Every nominal type this parameter's spelling mentions — `Box` and
    /// `Hidden` for `Box<Hidden>`. Read off the syntax tree; see
    /// ``TypeSyntax/nominalNames``.
    ///
    /// Consulted only where Zerk *adds* the parameter to a signature it did not
    /// write. A parameter the developer wrote needs no visibility check — it is
    /// already on a declaration the compiler accepted at that access — but a
    /// bubbled requirement comes from the dependency's provider, which can be
    /// less visible than the member resolving it.
    var typeNominalNames: Set<String> = []

    /// Whether the parameter is declared `inout`.
    ///
    /// The specifier survives in ``typeName`` and so reaches the emitted
    /// *signature* on its own. What it cannot reach is the forwarding *call*,
    /// which needs `&` — and every generated member forwards. One `inout`
    /// parameter on any provider was enough to emit a file that did not
    /// compile, with the error landing inside `Zerk.generated.swift`.
    ///
    /// `inout` is the only specifier that changes a call site. `borrowing`,
    /// `consuming`, `sending` and `@escaping` all forward by name, verified by
    /// type-checking each emitted shape.
    var isInout: Bool = false
    /// Whether the parameter is declared variadic.
    ///
    /// Carried in order to *refuse* it, not to reproduce it: the `...` lives on
    /// the parameter rather than on its type, so it was silently dropped and the
    /// member narrowed to a single element. Reproducing it does not work either
    /// — inside the member the parameter is an array, and Swift has no way to
    /// pass one on to a variadic — so a provider that declares one cannot be
    /// forwarded to at all, and saying so is the only honest answer.
    var isVariadic: Bool = false
    /// The parameter's own default value as written, when it has one and that
    /// text means the same thing anywhere.
    ///
    /// Without it a parameter Zerk cannot resolve became *mandatory* through
    /// Zerk while remaining optional on the declaration itself. The `@injected`
    /// overload path carried it all along, on ``MarkedParameter/defaultText`` —
    /// two models of a parameter, one of them complete.
    ///
    /// A default naming a magic literal is deliberately not carried; see
    /// ``FunctionParameterSyntax/portableDefaultText``.
    var defaultText: String? = nil

    /// Identity for matching a bubbled requirement to a parameter that can feed
    /// it: name and type, ignoring the label. The requirement's label comes from
    /// the *dependency's* declaration and need not match the member's.
    var resolutionIdentity: String { "\(name)|\(typeKey)" }

    /// Equality ignores the markers, the location and the generic facts: two
    /// parameters are interchangeable at a call site when their label, name and
    /// type agree, and `mergeParameters` dedupes on exactly that.
    ///
    /// The generic fields are deliberately out. They describe the *scope the
    /// parameter was read in*, not the parameter, so including them would make
    /// two identical `logger: Logger` parameters unequal for the sole reason
    /// that one of them was declared inside a generic type.
    static func == (lhs: ParameterRecord, rhs: ParameterRecord) -> Bool {
        lhs.label == rhs.label
            && lhs.name == rhs.name
            && lhs.typeKey == rhs.typeKey
            && lhs.typeName == rhs.typeName
    }
}
