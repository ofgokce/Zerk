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
