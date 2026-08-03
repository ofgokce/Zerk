//
//  ImportedInjectableMacro.swift
//  Zerk
//

/// Declares a dependency that lives in another module, so this module's graph
/// can resolve against it.
///
/// Zerk resolves within one module: its plugin reads this module's source and
/// knows nothing about another's. `@Injectable(public: true)` makes a key's
/// members public, but
/// the consuming module still has no idea the key exists, its effects, or its
/// isolation. This states all of that, in a form the compiler checks.
///
/// ```swift
/// enum ZerkImports {
///     @ImportedInjectable
///     static func session(baseURL: URL) -> Session
///
///     @ImportedInjectable
///     @MainActor
///     static func router() throws -> Routing
/// }
/// ```
///
/// Only the shape matters — the return type is the key, the parameters are what
/// the foreign provider needs, and `async`/`throws`/global-actor annotations
/// state its effects and isolation. The function's own name, visibility, and
/// whether it is global, `static`, or an instance method make no difference:
/// nothing ever calls it.
///
/// Written **without a body**, the macro synthesises `Zerk<Key>.inject(…)`, and
/// that expansion is the check — if the key is not exported, or its signature
/// differs, this line fails to compile rather than something further away.
///
/// Written **with a body**, the body names the member to resolve through instead
/// of the primary. It must be a single `Zerk` call and nothing else — no logic,
/// no locals — because Zerk inlines it at every use site:
///
/// ```swift
/// @ImportedInjectable
/// static func staging() -> Session { Zerk<Session>.staging }
/// ```
@attached(body)
public macro ImportedInjectable() = #externalMacro(
    module: "ZerkMacros",
    type: "ImportedInjectableMacro"
)
