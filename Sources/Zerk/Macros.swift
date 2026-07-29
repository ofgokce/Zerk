/// Registers a type or a value with the dependency graph.
///
/// On a type the key is the type itself; `@Injectable<Key>` registers it under
/// each listed key instead. On a `var` or `let` the declared type is the key
/// and the declaration supplies the value.
///
/// `method` applies to values only and controls whether the value is copied
/// into the generated member or read through to the original declaration —
/// see ``ValueInjectionMethod``. It is ignored on a type.
@attached(peer)
public macro Injectable(_ method: ValueInjectionMethod = .default) = #externalMacro(
    module: "ZerkMacros",
    type: "InjectableMacro"
)

@attached(peer)
public macro Injectable<each T>(_ method: ValueInjectionMethod = .default) = #externalMacro(
    module: "ZerkMacros",
    type: "InjectableMacro"
)

/// Registers every eligible static property of a type as an `@Injectable`
/// value, without annotating each one.
///
/// ```swift
/// @InjectableValues(.referenced)
/// enum AppConstants {
///     static let baseURL: String = "api.example.com"
///     static let retries: Int = 3
/// }
/// ```
///
/// A property is swept up when it is `static`, at least `internal`, and
/// declares an explicit type — Zerk reads syntax, so it cannot infer the type
/// that becomes the injection key. A `private` or `fileprivate` property is
/// skipped, since the generated file could not see it. Anything else in the
/// body — methods, nested types, instance properties — is left alone.
///
/// An individual property may carry its own `@Injectable(...)` to override the
/// method chosen here, or ``NonInjectable()`` to opt out entirely.
@attached(peer)
public macro InjectableValues(_ method: ValueInjectionMethod = .default) = #externalMacro(
    module: "ZerkMacros",
    type: "InjectableValuesMacro"
)

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

@attached(body)
public macro Providing() = #externalMacro(
    module: "ZerkMacros",
    type: "ProvidingMacro"
)

@attached(body)
public macro Providing<each T>() = #externalMacro(
    module: "ZerkMacros",
    type: "ProvidingMacro"
)

@attached(peer)
public macro Shared() = #externalMacro(
    module: "ZerkMacros",
    type: "SharedMacro"
)

@attached(peer)
public macro Shared<each T>() = #externalMacro(
    module: "ZerkMacros",
    type: "SharedMacro"
)

@attached(peer)
public macro Primary() = #externalMacro(
    module: "ZerkMacros",
    type: "PrimaryMacro"
)

@attached(peer)
public macro Primary<each T>() = #externalMacro(
    module: "ZerkMacros",
    type: "PrimaryMacro"
)

@attached(peer)
public macro Singleton() = #externalMacro(
    module: "ZerkMacros",
    type: "SingletonMacro"
)

/// Tells Zerk which global actor a declaration is isolated to, when the build
/// plugin cannot see it from syntax.
///
/// `@Isolated` is **corrective, not declarative**: it restates what the
/// compiler already believes so that Zerk mirrors the right isolation onto the
/// generated members. It does not change the declaration's actual isolation, so
/// claiming something untrue produces generated code that will not compile.
///
/// Two cases need it:
///
/// ```swift
/// // 1. A custom global actor whose name does not end in "Actor", which Zerk's
/// //    attribute heuristic cannot recognise.
/// @Isolated<DataStore>
/// @DataStore
/// @Injectable<Storing>
/// final class FileStore: Storing { init() {} }
///
/// // 2. Isolation inherited through a conformance, which the plugin cannot
/// //    follow across modules.
/// @Isolated<MainActor>
/// @Injectable<Storing>
/// final class UIStore: Storing, SomeMainActorProtocol { init() {} }
/// ```
///
/// For "this is nonisolated", use Swift's own `nonisolated` keyword — it is
/// real, and Zerk reads it.
@attached(peer)
public macro Isolated<A>() = #externalMacro(
    module: "ZerkMacros",
    type: "IsolatedMacro"
)

@attached(peer, names: prefixed(_$zerk_injection_))
public macro Injected() = #externalMacro(
    module: "ZerkMacros",
    type: "InjectedMacro"
)

@attached(peer, names: prefixed(_$zerk_injection_))
public macro Injected<T>(_ injectable: T) = #externalMacro(
    module: "ZerkMacros",
    type: "InjectedMacro"
)
