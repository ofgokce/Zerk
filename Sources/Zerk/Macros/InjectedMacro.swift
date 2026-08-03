//
//  InjectedMacro.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 2.08.2026.
//

/// Resolves a property from the graph when its enclosing value is initialized.
///
/// The generated file re-declares this macro inside the module it generates
/// into, adding an overload per distinct `inject()` signature so arguments can be
/// forwarded through the attribute, plus a key-path overload for naming a
/// specific member. Those module-local declarations shadow this one wherever the
/// build plugin runs — which is every target that declares injectables.
///
/// So this declaration is what a target *without* the plugin uses, and it is not
/// redundant: a module that declares no injectables of its own can still write
/// `@Injected var service: ApiServicing` against an exported key from another
/// module, because that key's members are public and this is the only
/// `@Injected` in scope there.
@attached(peer, names: prefixed(_$zerk_injection_))
public macro Injected() = #externalMacro(
    module: "ZerkMacros",
    type: "InjectedMacro"
)

/// Resolves a property from a key other than its own declared type.
///
/// The generic argument *is* the key, so the property can be declared as
/// anything the resolved value satisfies — a protocol it conforms to, a class it
/// subclasses, or an optional wrapping it:
///
/// ```swift
/// @Injected<LiveService> var service: Serving
/// ```
///
/// Compatibility is the compiler's to check: the generated peer assigns one to
/// the other, so a mismatch is rejected there with both real types named.
@attached(peer, names: prefixed(_$zerk_injection_))
public macro Injected<T>() = #externalMacro(
    module: "ZerkMacros",
    type: "InjectedMacro"
)

/// Resolves a property from one named `Zerk<Key>` member rather than the key's
/// primary.
///
/// The generated file declares this too, and shadows this one wherever the
/// plugin runs. It is repeated here so the form does not mysteriously stop
/// working in a target that happens to declare no injectables — without it, the
/// same attribute that compiles everywhere else fails there with "argument
/// passed to macro expansion that takes no arguments".
///
/// A target that exports nothing of its own can still name a member of another
/// module's exported key, since `@Injectable(public: true)` publicizes them all
/// — or one it declares itself:
///
/// ```swift
/// extension Zerk<ApiServicing> {
///     static var mock: ApiServicing { MockService() }
/// }
///
/// struct Preview {
///     @Injected(\.mock) var service: ApiServicing
/// }
/// ```
@attached(peer, names: prefixed(_$zerk_injection_))
public macro Injected<T>(_ keyPath: KeyPath<Zerk<T>.Type, T>) = #externalMacro(
    module: "ZerkMacros",
    type: "InjectedMacro"
)
