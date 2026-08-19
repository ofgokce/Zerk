//
//  Injectable.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 2.08.2026.
//

/// Registers a **type** with the dependency graph.
///
/// The key is the type itself; `@Injectable<Key>` registers it under each listed
/// key instead. Every key needs a way to be built — see
/// ``InjectableProviding()``.
///
/// Values are a different thing and have their own marker,
/// ``InjectableValue()``: a type is *built* by a provider, while a value is
/// *read* from a declaration, and the two are matched differently — a type by
/// its key, a value by key and name together. Applying this to a `var` or `let`
/// is an error naming the replacement.
///
/// ## Exporting a key
///
/// Zerk generates `internal` members by default, which keeps a module's graph
/// its own business. `public: true` opts a key out of that: `inject()` and
/// every named member for it become public, so a consuming module can resolve
/// the primary with `@Injected` or name one specific provider with
/// `@Injected(\.staging)`.
///
/// Like `primary`, it rides on the attribute that names the key, so a type
/// injectable under several can export some of them:
///
/// ```swift
/// @Injectable<Storing>(public: true)
/// @Injectable<Caching>
/// public final class Store: Storing, Caching { ... }
///
/// // Zerk<Storing> members are public; Zerk<Caching> members stay internal.
/// ```
///
/// The key type itself must be `public` — a public member cannot expose an
/// internal type — otherwise the request is dropped with a warning. A
/// `@Singleton`'s shared storage stays private regardless; only its getter is
/// exported.
///
/// `public` must be written as a `true`/`false` literal, for the same reason
/// `primary` must.
@attached(peer)
public macro Injectable() = #externalMacro(
    module: "ZerkMacros",
    type: "InjectableMacro"
)

@attached(peer)
public macro Injectable<each T>() = #externalMacro(
    module: "ZerkMacros",
    type: "InjectableMacro"
)

@attached(peer)
public macro Injectable(public: Bool) = #externalMacro(
    module: "ZerkMacros",
    type: "InjectableMacro"
)

@attached(peer)
public macro Injectable<each T>(public: Bool) = #externalMacro(
    module: "ZerkMacros",
    type: "InjectableMacro"
)

/// Registers a **type** and claims its keys for `Zerk<Key>.inject()`.
///
/// When several types are injectable under one key, exactly one of them must
/// be `primary` — that type is the one `inject()` builds. The others are still
/// generated as named members (`Zerk<Loading>.mock`), they simply do not win
/// the key.
///
/// ```swift
/// @Injectable<Loading>(primary: true)
/// final class LiveLoader: Loading { init() {} }
///
/// @Injectable<Loading>
/// final class MockLoader: Loading { init() {} }
///
/// Zerk<Loading>.inject()   // LiveLoader
/// Zerk<Loading>.mockLoader // still available
/// ```
///
/// This picks the winning *type*. Which of that type's providers builds it is
/// a separate choice — see ``InjectableProviding(primary:)``.
///
/// `primary` must be written as a `true`/`false` literal: Zerk reads syntax, so
/// it cannot evaluate a constant or a computed expression.
@attached(peer)
public macro Injectable(primary: Bool, public: Bool = false) = #externalMacro(
    module: "ZerkMacros",
    type: "InjectableMacro"
)

@attached(peer)
public macro Injectable<each T>(primary: Bool, public: Bool = false) = #externalMacro(
    module: "ZerkMacros",
    type: "InjectableMacro"
)

/// Registers the type a **global or static** declaration produces, with the
/// declaration as its provider.
///
/// The way a type you cannot annotate — `URLSession`, a vendor SDK's client —
/// becomes a real key rather than a value matched by name:
///
/// ```swift
/// @Injectable var urlSession: URLSession { .init(configuration: .default) }
///
/// Zerk<URLSession>.inject()      // and Zerk<URLSession>.urlSession
/// ```
///
/// The key is the declared or returned type, unless a generic argument states
/// one: `@Injectable<URLSessionProtocol> var urlSession: URLSession` registers
/// `URLSessionProtocol` and builds it from this.
///
/// The member takes the declaration's own name. Two arguments change that:
///
/// - `typeNamed: true` names it after the produced *type*, so a declaration
///   called anything yields `Zerk<URLSession>.urlSession`.
/// - `name:` names it outright, and takes a string literal — Zerk reads syntax
///   and cannot evaluate an expression or an interpolation.
///
/// They are alternatives; stating both is an error.
///
/// A generic function registers exactly as a generic type does — the key is the
/// family, and the member binds it per call:
///
/// ```swift
/// @Injectable(typeNamed: true)
/// func makeBox<X, Y>(x: X, y: Y) -> Box<X, Y> { … }
///
/// Zerk<Box<Int, String>>.box(x: 1, y: "a")
/// ```
@attached(peer)
public macro Injectable(typeNamed: Bool,
                        primary: Bool = false,
                        public: Bool = false) = #externalMacro(
    module: "ZerkMacros",
    type: "InjectableMacro"
)

@attached(peer)
public macro Injectable<each T>(typeNamed: Bool,
                                primary: Bool = false,
                                public: Bool = false) = #externalMacro(
    module: "ZerkMacros",
    type: "InjectableMacro"
)

/// Names the generated member outright. See ``Injectable(typeNamed:primary:public:)``.
@attached(peer)
public macro Injectable(name: String,
                        primary: Bool = false,
                        public: Bool = false) = #externalMacro(
    module: "ZerkMacros",
    type: "InjectableMacro"
)

@attached(peer)
public macro Injectable<each T>(name: String,
                                primary: Bool = false,
                                public: Bool = false) = #externalMacro(
    module: "ZerkMacros",
    type: "InjectableMacro"
)

/// Registers a generic type under a **parameterized existential** key: the
/// type's own parameters become the protocol's primary associated types.
///
/// ```swift
/// protocol Boxable<X, Y> { associatedtype X; associatedtype Y }
///
/// @Injectable<any Boxable>(parameterized: true)
/// struct Box<X, Y>: Boxable {
///     @InjectableProviding init(_ x: X, _ y: Y) { … }
/// }
///
/// Zerk<any Boxable<Int, String>>.inject(1, "a")
/// ```
///
/// It has to be asked for, because the same attribute without it means the
/// opposite — erase the parameters into a plain `any Boxable` — and both are
/// legal. The key cannot be written out in full: an attribute is resolved
/// outside the declaration's scope, so `@Injectable<any Boxable<X, Y>>` is
/// rejected by Swift itself with `'X' does not conform to 'Copyable'`.
///
/// The conformance must map positionally — the type's first parameter to the
/// protocol's first primary associated type, and so on. Zerk reads syntax and
/// cannot check that; a conformance that maps them differently is a compile
/// error on the generated member, naming both real types.
///
/// Parameterized existentials are iOS 16 / macOS 13 and later, so the generated
/// members carry an `@available` attribute.
@attached(peer)
public macro Injectable<each T>(parameterized: Bool, public: Bool = false) = #externalMacro(
    module: "ZerkMacros",
    type: "InjectableMacro"
)

@attached(peer)
public macro Injectable<each T>(primary: Bool,
                                parameterized: Bool,
                                public: Bool = false) = #externalMacro(
    module: "ZerkMacros",
    type: "InjectableMacro"
)
