//
//  ImportedInjectableValueMacro.swift
//  Zerk
//

/// Declares an `@Injectable` **value** that lives in another module, so this
/// module's graph can resolve parameters from it.
///
/// The companion to ``ImportedInjectable()``, which imports a *key*. The two are
/// separate because they are matched differently: a key import answers for its
/// key, while a value is matched by key **and name** together — which is what
/// stops two unrelated `String` values from being interchangeable. Importing a
/// value through the key form would discard the name and let one `String` answer
/// for every `String` parameter in the module.
///
/// ```swift
/// private enum ImportedInjectables {
///     @ImportedInjectableValue
///     static var baseURL: String { Zerk<String>.baseURL }
///
///     @ImportedInjectableValue
///     static var apiKey: String { Zerk<String>.apiKey }
/// }
/// ```
///
/// Both are imported under the one key `String` and stay distinct, because a
/// parameter has to be *named* `baseURL` to match the first.
///
/// The declaration is never called; only its shape is read. What matters is the
/// type annotation (the key), the declaration's own name (what parameters must
/// be called), and the getter naming the foreign member. Where it sits, how
/// visible it is, and whether it is `static` make no difference — though a
/// `private enum` keeps it out of the way.
///
/// **Renaming on import** falls out of that: the name on the left is local, the
/// member on the right is foreign, and they need not agree.
///
/// ```swift
/// @ImportedInjectableValue
/// static var apiBaseURL: String { Zerk<String>.baseURL }   // matches `apiBaseURL:`
/// ```
///
/// The getter is required and must be a single `Zerk` expression — Zerk inlines
/// it wherever the value is resolved, so it cannot hold other logic. Unlike the
/// key form there is nothing to synthesise when it is missing: there is no "the
/// primary `String`" to fall back on, so the member has to be named. That getter
/// is also the check — a value the other module did not export, or one whose
/// type differs, fails to compile right here.
///
/// Imported values are **read-only**. `= Zerk<String>.baseURL` is refused for
/// the same reason: it would capture the foreign value once instead of reading
/// it per resolution.
@attached(peer)
public macro ImportedInjectableValue() = #externalMacro(
    module: "ZerkMacros",
    type: "ImportedInjectableValueMacro"
)
