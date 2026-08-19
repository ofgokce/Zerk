//
//  ProviderKind.swift
//  Zerk
//

/// How the generated code calls a provider: `Type(...)` for an initializer,
/// `Type.name(...)` for a static factory, or the declaration itself for an
/// `@Injectable` var or func.
enum ProviderKind {
    case initializer
    case staticFunction(name: String)
    /// A global or static declaration carrying `@Injectable` — the way a type
    /// out of reach joins the graph. `reference` is what the generated member
    /// calls: `urlSession`, `Config.session`, `makeClient`.
    ///
    /// `isProperty` because this is the only provider that can be
    /// *property-shaped*. Every other one is called, so the emitter appends
    /// `()` unconditionally; a var must not get parentheses.
    ///
    /// `thunk` names a private forwarding function the generated file declares,
    /// used when the declaration is **global**. Inside `extension Zerk<Key>` an
    /// unqualified name resolves to the member being defined, so
    /// `static var urlSession: URLSession { urlSession }` is infinite recursion
    /// — the same hazard `@InjectableValue` solves the same way. A static member
    /// needs none: `Container.session` is already unambiguous.
    case declaration(reference: String, isProperty: Bool, thunk: String?)
}
