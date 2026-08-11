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

// MARK: - Dynamic resolution
//
// A separate attribute, and not by preference — this was twice specified as an
// argument on `@Injected`, and the compiler will not have it either way.
//
// The two variants have to generate structurally different things — a stored
// property initialized once, versus a computed property that resolves per access
// — so they need different macro *roles*: `@attached(peer)` above,
// `@attached(accessor)` here. **Overloads of one macro name must agree on their
// role set.** Adding a single accessor overload to `Injected` crashes SILGen on
// Swift 6.3.3 while lowering the *peer* expansion, on ordinary `@Injected`
// properties that have nothing to do with the new one. The argument's shape does
// not matter: a labelled `Bool` and a positional enum both do it.
//
// Making every overload declare both roles does stop the crash. It then forces
// the stored variant to produce a non-observing accessor — an observing one is
// rejected outright — which means `@Injected` becomes a computed property backed
// by its peer. That was built and measured, and it costs behaviour that is
// documented and load-bearing:
//
//   - with an `init` accessor: `final class C { @Injected var x: T }` stops
//     compiling — "class 'C' has no initializers";
//   - without one: the memberwise initializer can no longer override what was
//     injected, since the only stored property left is private;
//   - either way `@Injected let` and `willSet`/`didSet` are gone.
//
// No spelling is worth those. Keep every `Injected` overload a peer, and keep
// dynamic resolution under its own name.

/// Resolves a property from the graph on **every access**, rather than once when
/// its enclosing value is initialized.
///
/// `@Injected` stores what it resolved, which is right for almost everything:
/// one lookup, no per-access cost, and a reference that cannot change underneath
/// the holder. This is for the case where it *should* change — a `@Scoped`
/// dependency held by something that outlives the scope:
///
/// ```swift
/// @Injected            var stored: SessionCache   // resolved once, then kept
/// @InjectedDynamically var live: SessionCache     // re-resolved on every read
///
/// Zerk.reset(.session)
/// // `stored` still hands back the pre-reset instance; `live` sees the new one.
/// ```
///
/// The property becomes computed, so it must be a `var`, must have no
/// initializer, and cannot carry `willSet`/`didSet` — there is no storage left
/// for an observer to observe. It is also read-only: there is nowhere to put a
/// written value that the next read would not discard.
///
/// Every `@Injected` form has a counterpart here, spelled the same way: a key in
/// angle brackets, a key path, or arguments forwarded into `inject()`.
@attached(accessor)
public macro InjectedDynamically() = #externalMacro(
    module: "ZerkMacros",
    type: "InjectedDynamicallyMacro"
)

/// ``InjectedDynamically()`` resolving from a key other than the property's own
/// declared type.
@attached(accessor)
public macro InjectedDynamically<T>() = #externalMacro(
    module: "ZerkMacros",
    type: "InjectedDynamicallyMacro"
)

/// ``InjectedDynamically()`` resolving from one named `Zerk<Key>` member rather
/// than the key's primary.
@attached(accessor)
public macro InjectedDynamically<T>(_ keyPath: KeyPath<Zerk<T>.Type, T>) = #externalMacro(
    module: "ZerkMacros",
    type: "InjectedDynamicallyMacro"
)
