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

/// Not a real overload. It exists so that `@Injectable(.referenced)` reports
/// what to write instead — overload resolution would otherwise say "type 'Bool'
/// has no member 'referenced'", which names neither the problem nor the fix.
/// See ``InjectableValue(_:public:)``.
@attached(peer)
public macro Injectable(_ method: ValueInjectionMethod) = #externalMacro(
    module: "ZerkMacros",
    type: "InjectableMacro"
)

@attached(peer)
public macro Injectable<each T>(_ method: ValueInjectionMethod) = #externalMacro(
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
