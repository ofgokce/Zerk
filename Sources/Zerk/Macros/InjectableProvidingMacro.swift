//
//  InjectableProviding.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 2.08.2026.
//

/// Excludes a property from the sweep performed by `@InjectableValues`.
///
/// ```swift
/// @InjectableValues
/// enum AppConstants {
///     static let baseURL: String = "api.example.com"
///
///     @NonInjectable
///     static let buildStamp: String = "2026-07-29"   // not part of the graph
/// }
/// ```
///
/// Only meaningful inside a type marked `@InjectableValues`; elsewhere it does
/// nothing, since nothing was sweeping the property up to begin with. It
/// contradicts `@Injectable` on the same declaration, which is an error.
@attached(peer)
public macro NonInjectable() = #externalMacro(
    module: "ZerkMacros",
    type: "NonInjectableMacro"
)

/// Marks an initializer or `static` factory as a way to build an
/// `@Injectable`.
///
/// A type may declare **several** providers for one key; each becomes its own
/// named member under `Zerk<Key>`. `@InjectableProviding<Key>` binds a provider
/// to one specific key, while a bare `@InjectableProviding` serves every key the
/// type is injectable under — the two combine rather than shadowing each other.
///
/// ```swift
/// @Injectable<Loading>
/// final class Loader: Loading {
///     @InjectableProviding<Loading>(primary: true)
///     static func live() -> Loading { ... }
///
///     @InjectableProviding<Loading>
///     static func cached() -> Loading { ... }
/// }
///
/// Zerk<Loading>.live       // both members exist
/// Zerk<Loading>.cached
/// Zerk<Loading>.inject()   // live, because it is primary
/// ```
///
/// When a type has more than one provider for a key, whichever one `inject()`
/// should call must be marked `primary`. It is only required of the type that
/// actually wins the key — see ``Injectable(primary:)``.
///
/// A factory's member takes the factory's own name and an initializer's takes
/// its type's. Both can be changed — see
/// ``InjectableProviding(typeNamed:primary:)`` and
/// ``InjectableProviding(name:primary:)``.
@attached(body)
public macro InjectableProviding() = #externalMacro(
    module: "ZerkMacros",
    type: "ProvidingMacro"
)

@attached(body)
public macro InjectableProviding<each T>() = #externalMacro(
    module: "ZerkMacros",
    type: "ProvidingMacro"
)

/// Marks a provider, and states whether it is the one `inject()` calls.
///
/// `primary` must be written as a `true`/`false` literal: Zerk reads syntax, so
/// it cannot evaluate a constant or a computed expression.
@attached(body)
public macro InjectableProviding(primary: Bool) = #externalMacro(
    module: "ZerkMacros",
    type: "ProvidingMacro"
)

@attached(body)
public macro InjectableProviding<each T>(primary: Bool) = #externalMacro(
    module: "ZerkMacros",
    type: "ProvidingMacro"
)

/// Marks a factory, and names the member it generates after the type it
/// returns.
///
/// A factory's member is called what the factory is called, which is the right
/// default when the two live together — `Zerk<Loading>.live`. It is the wrong
/// one when the factory only exists to build a type from somewhere else, since
/// then its name says nothing about the key:
///
/// ```swift
/// @Injectable<URLSession>
/// enum SessionProvider {
///     @InjectableProviding(typeNamed: true)
///     static func live() -> URLSession { .init(configuration: .default) }
/// }
///
/// Zerk<URLSession>.urlSession    // rather than .live
/// ```
///
/// The name comes from the **return type**, not from the key or the enclosing
/// type: a factory returning `URLSession` yields `urlSession` whatever it is
/// declared inside and whatever key it is bound to.
///
/// Only a factory takes this. An initializer can only ever produce its own
/// type, so its member is named after that type already — writing it there is
/// an error naming ``InjectableProviding(name:primary:)`` as the way to change
/// it.
///
/// Naming is per attribute, as `primary` is: a factory bound to two keys can
/// be named differently under each.
@attached(body)
public macro InjectableProviding(typeNamed: Bool, primary: Bool = false) = #externalMacro(
    module: "ZerkMacros",
    type: "ProvidingMacro"
)

@attached(body)
public macro InjectableProviding<each T>(typeNamed: Bool, primary: Bool = false) = #externalMacro(
    module: "ZerkMacros",
    type: "ProvidingMacro"
)

/// Marks a provider, and names the member it generates outright.
///
/// Takes a string literal — Zerk reads syntax and cannot evaluate an expression
/// or an interpolation. Unlike `typeNamed:`, this applies to an initializer
/// too, which is otherwise stuck with its type's name:
///
/// ```swift
/// @Injectable<Loading>
/// struct Loader: Loading {
///     @InjectableProviding(name: "live")
///     init() {}
/// }
///
/// Zerk<Loading>.live    // rather than .loader
/// ```
///
/// Stating this alongside `typeNamed: true` is an error; they name the same
/// member two ways.
@attached(body)
public macro InjectableProviding(name: String, primary: Bool = false) = #externalMacro(
    module: "ZerkMacros",
    type: "ProvidingMacro"
)

@attached(body)
public macro InjectableProviding<each T>(name: String, primary: Bool = false) = #externalMacro(
    module: "ZerkMacros",
    type: "ProvidingMacro"
)
