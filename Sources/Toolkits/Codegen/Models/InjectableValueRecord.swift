//
//  InjectableValueRecord.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

/// An `@Injectable` *value* — a static property rather than a type, e.g.
/// `@Injectable static var apiKey: String`.
///
/// Values are matched to parameters by type key **and name** together, which is
/// what stops two unrelated `String` values from being interchangeable.
/// `bodyText` is the getter's *statements*, `return` included, re-emitted into
/// the generated member so the value is recomputed per resolution rather than
/// captured once. Statements rather than an expression because a body may have
/// several, and because the generated getter opens with the interjection guard —
/// which is what takes Swift's implicit single-expression return off the table.
struct InjectableValueRecord {
    let name: String
    /// `var` so the alias pass can fold it onto its group's representative.
    var typeKey: String
    let typeName: String
    /// How the key is written in the generated file: the canonical spelling with
    /// `any` as the developer wrote it. `nil` falls back to the key itself.
    var keyDisplayName: String? = nil
    let bodyText: String?
    let location: AttributeLocation
    /// Values participate in the isolation model exactly like type providers:
    /// the body may touch isolated state, and under an ambient `MainActor`
    /// default an unannotated `@InjectableValue var` is `@MainActor`.
    var isolation: ProviderIsolation = .nonisolated
    /// Whether the generated member copies the declaration's body or reads
    /// through to it. Already resolved against `ZerkSettings` — never
    /// `.default` by this point.
    var injectionMethod: ValueInjectionMethod = .copied
    /// Dot-joined names of the enclosing types, e.g. `"AppConstants"`, or `nil`
    /// for a top-level declaration.
    ///
    /// `.referenced` needs it to qualify the read: a bare name inside
    /// `extension Zerk<T>` resolves to the generated member itself, so an
    /// unqualified reference would recurse. Top-level values have no qualifier
    /// available and go through a file-scope thunk instead.
    var enclosingTypePath: String? = nil
    /// The parameters of a `@InjectableValue static func`, empty for a property.
    ///
    /// A parametric value is matched by key and name like any other, but its own
    /// parameters behave exactly as a provider's: resolved from the graph where
    /// they can be, bubbled to the consumer where they cannot, and honouring the
    /// parameter markers. `var` so the alias pass can fold their keys.
    var parameters: [ParameterRecord] = []
    /// The `async`/`throws` a getter declares, which the generated member
    /// restates and every resolution through it propagates — exactly as a
    /// provider's do.
    ///
    /// Only a getter can carry them: Swift has no effectful setter, so an
    /// effectful value is read-only, and a stored declaration has no accessor to
    /// put them on.
    var effects: ProviderEffects = .none
    /// Whether the source can be assigned — a `var` that is stored or has a
    /// setter. Only then does the generated member get a setter.
    var isSettable: Bool = false
    /// Whether `@Injectable(public: true)`, or an enclosing
    /// `@InjectableValues(public: true)`, asked for the generated member to be
    /// `public`. Whether it *can* be is settled at emission, where the key's
    /// access level is known — only the key appears in the member's signature,
    /// so the source declaration's own access level does not constrain this.
    var isExported: Bool = false

    /// Set when the value lives in **another** module, to the expression that
    /// reads it there. Two things follow: no member is emitted for it here — the
    /// declaring module already has one — and resolution goes through this
    /// rather than through a member of this module's own.
    ///
    /// It cannot be reassembled from `keyText` and `name`, because an import may
    /// be renamed: `var apiBaseURL: String { Zerk<String>.baseURL }` matches
    /// parameters called `apiBaseURL` while reading a member called `baseURL`.
    var importedExpression: String? = nil

    /// The spelling every `Zerk<Key>` naming this value uses, so the extension
    /// declaring the member and the expressions reading it agree.
    var keyText: String { keyDisplayName ?? typeKey }

    /// Whether this record came from another module, and so emits nothing here.
    var isImported: Bool { importedExpression != nil }

    /// Whether the value is a function rather than a property, and so is built
    /// through the provider machinery instead of emitted as a `static var`.
    var isParametric: Bool { !parameters.isEmpty }

    /// How the generated member reaches the developer's own declaration.
    ///
    /// A nested one is qualified; a top-level one cannot be, because an
    /// unqualified name inside `extension Zerk<Key>` resolves to the generated
    /// member itself and would recurse — the same reason a `.referenced` value
    /// goes through a file-scope thunk.
    var parametricCallee: String {
        enclosingTypePath.map { "\($0).\(name)" } ?? "_$zerk_call_\(name)"
    }

    /// The parametric form as a `ProviderResolution`, so it can travel the
    /// provider path — parameter classification, defaults, bubbling, the split
    /// variants, the interjection requirement — instead of duplicating it.
    ///
    /// Never a primary: a value is reached by name, so it cannot win its key's
    /// `inject()` however many parameters it takes.
    var providerResolution: ProviderResolution {
        ProviderResolution(
            typeName: typeName,
            injectableKey: typeKey,
            provider: .value(self),
            isTypePrimary: false,
            isExported: isExported,
            isSingleton: false
        )
    }

    /// Identity in the parametric lookup: values are matched by key *and* name.
    var matchIdentity: String { "\(typeKey)|\(name)" }

    /// How a resolution reads this value, wherever it lives.
    var resolutionExpression: String { importedExpression ?? "Zerk<\(keyText)>.\(name)" }
}
