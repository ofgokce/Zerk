//
//  InjectableValueRecord.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

/// An `@InjectableValue` — a static property rather than a type, e.g.
/// `@InjectableValue static var apiKey: String`.
///
/// A property, always: `@InjectableValue` does not apply to a function. A value
/// is *read* from a declaration, and something with parameters is built rather
/// than read — which is what `@Injectable` on a global or `static` func
/// registers, as a real type key.
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
    /// `extension Zerk<Key>` resolves to the generated member itself, so an
    /// unqualified reference would recurse. Top-level values have no qualifier
    /// available and go through a file-scope thunk instead.
    var enclosingTypePath: String? = nil
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

    /// The `#if` clauses this declaration sits inside, which its generated
    /// member is emitted under. See ``CompilationCondition``.
    var condition: CompilationCondition = .unconditional

    /// The spelling every `Zerk<Key>` naming this value uses, so the extension
    /// declaring the member and the expressions reading it agree.
    var keyText: String { keyDisplayName ?? typeKey }

    /// Whether this record came from another module, and so emits nothing here.
    var isImported: Bool { importedExpression != nil }

    /// How a value is matched and deduped: by key *and* name together.
    var matchIdentity: String { "\(typeKey)|\(name)" }

    /// How a resolution reads this value, wherever it lives.
    var resolutionExpression: String { importedExpression ?? "Zerk<\(keyText)>.\(name)" }
}
