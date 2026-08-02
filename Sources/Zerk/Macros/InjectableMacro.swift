//
//  Injectable.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 2.08.2026.
//

/// Registers a type or a value with the dependency graph.
///
/// On a type the key is the type itself; `@Injectable<Key>` registers it under
/// each listed key instead. On a `var` or `let` the declared type is the key
/// and the declaration supplies the value.
///
/// The two arguments apply to opposite halves of that: ``ValueInjectionMethod``
/// is meaningful on a value only, `primary` on a type only. Neither overload
/// accepts both, and passing one to the wrong kind of declaration is an error
/// rather than a silently ignored argument.
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

/// Registers a **value** and states how the generated member reaches it.
///
/// `method` controls whether the value is copied into the generated member or
/// read through to the original declaration — see ``ValueInjectionMethod``.
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
public macro Injectable(primary: Bool) = #externalMacro(
    module: "ZerkMacros",
    type: "InjectableMacro"
)

@attached(peer)
public macro Injectable<each T>(primary: Bool) = #externalMacro(
    module: "ZerkMacros",
    type: "InjectableMacro"
)
