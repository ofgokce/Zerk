# Zerk

[![Swift Package Manager](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-brightgreen.svg?style=flat)](https://github.com/apple/swift-package-manager)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platforms](https://img.shields.io/badge/platforms-iOS%2013%2B%20%7C%20macOS%2014%2B%20%7C%20macCatalyst%2013%2B%20%7C%20watchOS%206%2B%20%7C%20tvOS%2013%2B%20%7C%20visionOS%201%2B-lightgrey.svg)](#requirements)
[![Swift Version](https://img.shields.io/badge/Swift-6.0-F16D39.svg?style=flat)](https://developer.apple.com/swift)

Zerk is a compile-time dependency injection framework for Swift. Instead of a runtime container, it combines Swift macros with a build-tool plugin that scans your module's source, resolves the dependency graph during the build, and generates plain static factory code on a `Zerk<T>` namespace. There is nothing to register at runtime, resolution failures are build errors with file/line locations, and injected code is ordinary Swift you can step through.

For testing, the same plugin also generates a per-key `Interjecting<Key>` protocol. A test suite conforms `Zerk` to it to swap any injectable for a double without touching production code — a plain, compile-checked protocol conformance.

## What's changed

Zerk 2 is a ground-up replacement for the original runtime container:

- Dependency registration moved from runtime calls like `Zerk.store.singleton(...)` to source annotations read by `ZerkPlugin`.
- Resolution moved from `Zerk.standardStorage.restore()` to generated members on `Zerk<Key>`, usually reached through `Zerk<Key>.inject()` or `@Injected`.
- Missing providers, ambiguous providers, cycles, unsupported singletons, and isolation mismatches are reported during the build instead of failing at runtime.
- Swift concurrency is modeled directly: generated injectors mirror provider isolation, propagate `async`/`throws`, and reject constructs that Swift cannot express safely.
- Test overrides are compile-checked through generated `Interjecting<Key>` protocols instead of mutating a shared container.
- Installation is Swift Package Manager only; CocoaPods-era runtime APIs and key-path property injection wrappers are no longer part of the public model.

## Migration

For an app using Zerk 1.x, migrate one module at a time:

1. Replace the dependency with Swift Package Manager and attach `ZerkPlugin` to each target that declares injectable types or values. Remove CocoaPods integration for Zerk.
2. Delete central registration code (`Zerk.store`, `AutoStoring`, `transient`, `scoped`, and `singleton` chains). The graph now comes from declarations in the source files themselves.
3. Mark injectable implementations with `@Injectable` or `@Injectable<Protocol>`. Use `@Singleton` for the old singleton lifetime, and leave non-singletons unmarked for transient factory-style construction.
4. Mark each initializer or static factory Zerk may call with `@InjectableProviding`. If there is exactly one initializer and no provider is marked, Zerk infers it. A key with several providers needs one of them marked `@InjectableProviding(primary: true)`.
5. Convert registered constants or configuration values into `@Injectable` values, or group static constants under `@InjectableValues`.
6. Replace manual restores with `Zerk<Key>.inject()`. Replace property injection with `@Injected var dependency: Key` when the dependency can be resolved synchronously.
7. For initializer or method parameters that should be filled automatically, use lowercase `@injected` on the parameter and call the generated overload.
8. Move tests from container mutation to interjection: `@testable import` the declaring module and conform `Zerk` to the generated `Interjecting<Key>` protocol for the member you want to override.
9. Add `ZerkSettings.json` if your target uses Swift 5 language mode, `SWIFT_DEFAULT_ACTOR_ISOLATION`, or a non-default value injection policy.

Key-path wrappers from 1.x such as `@InjectedProperty`, `@InjectedMutableProperty`, and `@InjectedMethod` do not have direct 2.x equivalents. Inject the dependency itself, or expose the needed operation through a small protocol and inject that protocol.

## Requirements

- Swift 6.0 **toolchain** (`swift-tools-version: 6.0`); Zerk's own targets build in `.v6` language mode
- swift-syntax 600.x
- Platforms: iOS 13+, macOS 14+, watchOS 6+, tvOS 13+, visionOS 1+, Mac Catalyst 13+

### Consuming targets in Swift 5 language mode

Your target does **not** have to be in Swift 6 language mode. A target with `SWIFT_VERSION = 5` under a Swift 6 toolchain (Xcode 16 or later) is fully supported, with one exception:

| Your graph | `SWIFT_VERSION = 5` | Swift 6 |
|---|---|---|
| Nonisolated providers | works | works |
| `@Singleton`, isolated or not | works | works |
| Isolated provider, nonisolated dependency | works | works |
| Isolated provider, dependency in *another* domain | works (resolves via `async`) | works |
| Isolated provider, dependency in the **same** domain | needs an opt-in, below | works |

The last row is the only one SE-0411 governs: Zerk resolves such a dependency into a default argument, and a Swift 5 target evaluates that expression at the *caller* unless you opt in. Either of these unlocks it, independently:

- `SWIFT_UPCOMING_FEATURE_ISOLATED_DEFAULT_VALUES = YES` — the narrow opt-in, and the one to prefer, or
- `SWIFT_STRICT_CONCURRENCY = complete`

Then tell Zerk, since the plugin cannot read your build settings:

```jsonc
{ "swiftVersion": "5", "isolatedDefaultValues": true }
```

Without one of these, Zerk emits a build error naming the providers rather than generating code that cannot compile. Every other isolated construct generates normally.

## Installation

Attach the build plugin to every target that **declares** injectables. Test targets do not need it — they reach interjection through `@testable import`:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/ofgokce/Zerk.git", from: "2.0.0"),
],
targets: [
    .target(
        name: "App",
        dependencies: [.product(name: "Zerk", package: "Zerk")],
        plugins: [.plugin(name: "ZerkPlugin", package: "Zerk")]
    ),
    .testTarget(
        name: "AppTests",
        dependencies: ["App"]        // no plugin needed
    ),
]
```

The package vends two products: the `Zerk` library (the macros and the `Zerk<T>` namespace) and the `ZerkPlugin` build-tool plugin.

The plugin generates the injectors **and** the `Interjecting<Key>` protocols into the module that declares the injectables. A test target that does `@testable import App` sees those (internal) protocols and conforms `Zerk` to them; the interjection guards already compiled into `App` resolve the conformance at runtime. Attach the plugin to a test target only if that target itself declares injectables (as this package's own `ZerkTests` does, because its fixtures live in the test target). In an Xcode project, add `ZerkPlugin` under the declaring target's Build Phases → Run Build Tool Plug-ins.

## Quick start

```swift
import Zerk

// 1. A value the graph can use to satisfy parameters of matching type
@Injectable
var baseURL: String {
    "https://api.example.com"
}

// 2. An injectable keyed by a protocol
protocol ApiServicing: AnyObject {
    var host: String { get }
}

@Singleton
@Injectable<ApiServicing>
final class ApiService: ApiServicing {
    let host: String

    @InjectableProviding
    init(baseURL: String) {       // `baseURL: String` auto-satisfied by the value above
        self.host = baseURL
    }
}

// 3. A consumer
struct FeedViewModel {
    @Injected
    var apiService: ApiServicing   // resolved at init, at compile-time-verified call site
}
```

The plugin generates (roughly):

```swift
extension Zerk<ApiServicing> {
    nonisolated(unsafe) static let apiService: ApiServicing = {
        // Test suites can override this via the interjection protocol below.
        if let interjector = Self.self as? any InterjectingApiServicing.Type,
            let interjected = interjector.interjectedApiService {
            return interjected
        }
        return ApiService(baseURL: Zerk<String>.baseURL)
    }()

    static func inject() -> ApiServicing { apiService }
}

// Also generated, one per key, for tests to conform to:
protocol InterjectingApiServicing {
    static nonisolated var interjectedApiService: ApiServicing? { get }
}
```

`@Injected var apiService` expands to a stored property whose default value is `Zerk<ApiServicing>.inject()`. `Zerk<T>` itself is an empty `public enum Zerk<T> {}`; everything lives in the generated extensions.

## How it works

Zerk is a macro package and a build-tool plugin, and it is worth knowing which does what — because **almost none of the code generation happens in the macros.**

`@Injectable`, `@InjectableProviding`, `@Shared`, `@Singleton`, and `@Isolated` expand to *nothing*. They exist so the attribute is legal Swift for the plugin to read, and so the errors that *are* decidable from a single declaration — a type that does not conform to the key it claims, a missing `@InjectableProviding`, an `@Isolated` contradicting a `nonisolated` modifier — are reported right at the declaration. `@Injected` is the one macro that generates code, because the expression it needs (`Zerk<T>.inject()`) depends on nothing but the property's own type.

Everything else is the plugin, for one reason: an attached macro can only see the declaration it is attached to, while resolving a dependency graph requires the whole module. So `ZerkPlugin` runs `ZerkCodegen` over every `.swift` file in the target, in three stages:

1. **Collect** — walk the syntax and record injectable types and values, their providers, `@Injected` uses, and members carrying `@injected` parameters.
2. **Resolve** — collect every provider for each key, elect the one that backs `inject()`, and report the cases that are ambiguous or impossible.
3. **Generate** — classify each provider's parameters, then emit the `Zerk<Key>` extensions, the `Interjecting<Key>` protocols, and the `Sendable` checks singletons need.

The output is a single `ZerkGenerated/ZerkInjections.swift` in the build directory, declared as the command's only output so the build system reruns codegen exactly when a source file or `ZerkSettings.json` changes.

One consequence runs through the whole design: **the plugin reads syntax, never resolved types.** It cannot see through an unmarked `typealias`, cannot follow a conformance into another module, and cannot read your build settings. That is why type keys are canonicalized only as far as syntax allows, why `@Isolated<A>` exists, and why `ZerkSettings.json` exists.

## Macro reference

### Declaring injectables

**`@Injectable` / `@Injectable<Key1, Key2, …>`** — marks a class, struct, enum, actor, or a typed variable as injectable. Without generic arguments the type itself is the key; with them, each listed type (typically a protocol) is a key. On a variable, the declared type is the key and the body becomes the injected value:

```swift
@Injectable
var timeout: TimeInterval { 30 }
```

Values participate in resolution: any provider parameter whose type matches a uniquely-declared value is filled in automatically. A value declared inside a type must be `static`, and values are matched by type **and name** together — which is what stops two unrelated `String` values from being interchangeable.

**Copied vs. referenced values.** By default a value's body is *copied* into the generated member, which then never reads the original — so a later write to the source is invisible to injection. Pass `.referenced` to read through to the declaration instead, which is what you want for anything updated at runtime:

```swift
enum Settings {
    @Injectable(.referenced)
    nonisolated(unsafe) static var baseURL: String = "api.example.com"
}

Settings.baseURL = "staging.example.com"
Zerk<String>.baseURL        // "staging.example.com" — follows the source
Zerk<String>.baseURL = "x"  // writes back to Settings.baseURL
```

A settable source produces a settable member; a `let` or a get-only computed property stays read-only. The source must be at least `internal`, since the generated file has to see it — a `private` value can only be copied. The default is `.copied`, and `valueInjectionMethod` in `ZerkSettings.json` changes it globally.

**`@InjectableValues`** — registers every eligible static property of a type, so a constants namespace does not need an attribute per member:

```swift
@InjectableValues(.referenced)
enum AppConstants {
    nonisolated(unsafe) static var baseURL: String = "api.example.com"
    static let retries: Int = 3

    @NonInjectable
    static let buildStamp: String = "2026-07-29"   // opted out
}
```

A property is swept up when it is `static`, at least `internal`, and declares an explicit type — the type *is* the injection key, and a syntax-only plugin cannot infer it, so a missing annotation is an error rather than a silent skip. `private` and `fileprivate` members, instance properties, methods, and nested types are left alone. An individual property may carry its own `@Injectable(...)` to override the method, or **`@NonInjectable`** to opt out entirely.

**`@InjectableProviding`** — marks a way to build the type. Place on an initializer or a `static` factory function. `@InjectableProviding<Key>` binds a provider to one specific key when a type is injectable under several; a bare `@InjectableProviding` serves every key the type claims. The two **combine** rather than shadowing each other, so a key can be served by both at once.

If no provider is marked at all, Zerk infers one from a single initializer, including synthesized memberwise (structs) and default initializers. Marking any provider suppresses that inference — declaring one is a deliberate choice, and a bare initializer must not silently join it. A type with multiple initializers and no marked provider is an error.

```swift
@Injectable<UserService>
final class LiveUserService: UserService {
    @InjectableProviding<UserService>
    static func live(apiService: ApiServicing, logger: Logger) -> UserService { ... }
}
```

A key may have **several** providers, each generated as its own named member. When it does, the one `inject()` should call is marked `primary`:

```swift
@Injectable<Loading>
final class Loader: Loading {
    @InjectableProviding<Loading>(primary: true)
    static func live() -> Loading { ... }

    @InjectableProviding<Loading>
    static func cached() -> Loading { ... }
}

Zerk<Loading>.live       // both members exist
Zerk<Loading>.cached
Zerk<Loading>.inject()   // live, because it is primary
```

`primary` must be a `true`/`false` literal — Zerk reads it from source and cannot evaluate an expression. It is only *required* of the type that wins the key (see `@Injectable(primary:)` below); writing it on a lone provider is accepted and has no effect.

Providers that share a member name are fine as long as their parameters differ — two marked initializers are both named after their type, and the generated overloads are told apart exactly as the initializers are.

Provider parameters are resolved in this order: a uniquely matching `@Injectable` value → a uniquely resolvable injectable key (recursively) → otherwise the parameter is exposed on the generated member and on `inject(...)` for the caller to supply ("parametric injection").

**`@Singleton`** — one shared instance per *type*, created lazily and thread-safely on first access. A type injectable under several keys is built once and every key returns that same instance. Reference types (class/actor) only. Singleton providers cannot be `async`/`throws` and cannot require external arguments, and a singleton must resolve to one provider across all of its keys — one instance cannot be built two ways.

**`@Injectable(primary:)`** — when several *types* are injectable under the same key, marks the one `inject()` should build. Exactly one must claim it; leaving the key contested is a build error. The others are still generated as named members (`Zerk<Loading>.mockLoader`), they simply do not win the key.

```swift
@Injectable<Loading>(primary: true)
final class LiveLoader: Loading { init() {} }

@Injectable<Loading>
final class MockLoader: Loading { init() {} }

Zerk<Loading>.inject()      // LiveLoader
Zerk<Loading>.mockLoader    // still available
```

The two `primary` flags are independent axes: `@Injectable(primary:)` picks the winning **type**, `@InjectableProviding(primary:)` picks the winning **provider within that type**. `inject()` is the intersection. A type that loses the key never needs a primary among its own providers.

Like every Zerk attribute it applies per key, so `@Injectable<A>(primary: true) @Injectable<B>` claims `A` only. It is a *type*-only argument: a value is the sole provider for its key, so `primary` on one is an error.

**`@ZerkAlias` / `#ZerkAlias<A, B, …>()`** — tells Zerk that two names are one key. Zerk matches by spelling, so without this a provider registered as `Storing` will not satisfy a parameter written `Persisting`:

```swift
@ZerkAlias
typealias Persisting = Storing        // the typealias is in this target

#ZerkAlias<Storing, Caching>()        // it is not — list the types instead
```

Merging is not just convenience. `Zerk<Storing>` and `Zerk<Persisting>` are the *same* generic specialization, so registering an injectable under each would emit two `inject()` members on one type — `invalid redeclaration of 'inject()'`. Equivalence is transitive, and the group is represented by the underlying type where there is one (`@ZerkAlias typealias Names = [String]` emits `Zerk<Array<String>>`), otherwise by the alphabetically first name.

The freestanding form expands to a private, never-called function that pairs the listed types through a generic same-type parameter, so **the compiler** checks the claim — listing types that are not interchangeable is a build error at the `#ZerkAlias` line. The check is invariant, so a subclass and its superclass are correctly rejected. The trailing `()` is required: written bare, Swift does not hand the generic arguments to the macro.

Generic typealiases are rejected — substituting their parameters would need real type resolution. Alias a concrete instantiation instead.

**`@Shared`** — makes the generated `inject()` `public`, so other modules can resolve the key. The key type itself must be `public`, otherwise the modifier is dropped with a warning.

**`@Isolated<A>`** — tells Zerk which global actor a declaration is isolated to, when the build plugin cannot see it. It is **corrective, not declarative**: it restates what the compiler already believes so the generated members mirror the right isolation. Claiming something untrue produces generated code that will not compile. Two cases need it — a custom global actor whose name does not end in `Actor` (Zerk's attribute heuristic misses it), and isolation inherited through a conformance (invisible to a syntax-only plugin):

```swift
@Isolated<DataStore>
@DataStore
@Injectable<Storing>
final class FileStore: Storing { init() {} }
```

For "this is nonisolated", use Swift's own `nonisolated` keyword — it is real, and Zerk reads it. `@Isolated` may be attached to a type, an initializer, an `@InjectableProviding` factory, or an `@Injectable` value; the innermost annotation wins, exactly as Swift's own isolation inference works.

### Consuming injectables

**`@Injected`** — resolves eagerly when the enclosing value is initialized. Variants:

```swift
@Injected var service: ApiServicing                 // Zerk<ApiServicing>.inject()
@Injected(seed: 100) var token: SeededToken         // forwards args to inject(seed:)
@Injected(Zerk<ApiServicing>.mock) var s: ApiServicing  // explicit expression
```

`@Injected` requires an explicit type annotation and works with optionals (`Service?` resolves `Service`). A value passed to the memberwise initializer still wins over the injected default, so a caller can override what gets injected.

**Lazy resolution** — there is no `@LazyInjected` macro. Use a plain `lazy var` calling `Zerk<Key>.inject()` directly, which is clearer and has no macro caveats:

```swift
final class Consumer {
    lazy var token: SeededToken = Zerk<SeededToken>.inject(seed: 100)
}
```

**`@injected` (lowercase) — parameter injection.** Marks an initializer or method parameter; the build plugin generates an overload with every marked parameter omitted and filled via `Zerk<T>.inject()`:

```swift
final class AuditTrail {
    init(@injected logger: Logger, label: String) { ... }
}

AuditTrail(label: "audit")                    // generated overload, logger injected
AuditTrail(logger: myLogger, label: "manual") // original init, untouched
```

The lowercase name is deliberate: `@Injected` is the property macro, `@injected` the parameter marker (case-sensitive, so they never collide). It has to be a property wrapper rather than a macro because Swift attached macros cannot apply to parameters; the wrapper is inert, so call sites of the original signature are unaffected. Class inits get a `convenience` overload; structs, actors, and enums get a plain extension init; methods get a delegating overload. Constraints: the marked parameter's type must be resolvable argument-free in the module (`@Injectable`, non-parametric provider), no default values on marked parameters, no variadic or `inout` parameters, no generic types/members, and the member must be at least `internal`. Async or throwing chains are allowed — and so are cross-domain ones, which merge in as `async` — so the generated overload becomes `async`/`throws` accordingly. This is the one injection path that supports effectful construction.

**Manual resolution** — `Zerk<Key>.inject()` (or `try await Zerk<Key>.inject(...)` for effectful chains) anywhere.

### Async and throwing providers

Effects propagate through the chain: if a provider is `async`/`throws`, the generated members and `inject()` are too, and transitive dependents inherit the effects. `@Injected` expands to a synchronous accessor and cannot resolve such chains (the codegen emits an error if you try); resolve them manually, or use an `@injected` parameter, whose generated overload inherits the chain's effects.

## Testing with interjection

For every generated injector member, the plugin also emits a mirror requirement on a per-key protocol named `Interjecting<Key>`, and each generated member checks — at the top of its body — whether `Zerk<Key>` conforms:

```swift
// Generated:
protocol InterjectingUserService {
    static func interjectedLive(apiService: ApiServicing, logger: Logger) -> UserService?
}
protocol InterjectingSeededToken {
    static func interjectedSeeded(seed: Int) -> SeededToken?
}
```

These protocols are `internal` to the declaring module, so the test target reaches them with `@testable import App` — no plugin on the test target. A test suite overrides an implementation by conditionally conforming `Zerk` to the protocol. Returning a value overrides injection; returning `nil` falls through to the real provider — so you can gate overrides behind a flag and leave production code untouched:

```swift
@testable import App

struct MockUserService: UserService {
    func requestPath() -> String { "mock/users" }
    var loggerSerial: Int { -1 }
}

extension Zerk: InterjectingUserService where T == UserService {
    static func interjectedLive(apiService: ApiServicing, logger: Logger) -> UserService? {
        MockUserService()
    }
}

// A parameterized provider is overridden the same way, bypassing the real factory:
extension Zerk: InterjectingSeededToken where T == SeededToken {
    static func interjectedSeeded(seed: Int) -> SeededToken? {
        SeededToken(value: 999)
    }
}
```

The interjected member name is `interjected` + the capitalized generated member name (so `Zerk<Loading>.live` → `interjectedLive`), and it mirrors the generated member's parameters. Property-shaped members (values, singletons, argument-free providers) become a `var interjected…: Key? { get }` requirement instead. Because interjection is an ordinary protocol conformance, renaming a provider surfaces as a *compile error* on the stale conformance rather than silently falling through.

## Swift 6 concurrency model

Zerk's rule is: **a generated member's isolation is its provider's isolation.** Whatever a provider is isolated to — nothing, a global actor, or an actor's nonisolated init — the member built for it says the same thing explicitly, so the generated file's meaning never depends on a build flag.

Isolation does not merge. There is no join of `MainActor` and `DatabaseActor`, so a dependency in a *different* domain does not change the member's isolation — it converts into an `async` effect instead:

| dependency | member | cost |
|---|---|---|
| nonisolated | any | none — synchronous call |
| same domain | same domain | none — synchronous call |
| domain A | domain B, or nonisolated | the member becomes `async` |
| `actor` | any | none — a sync actor init is nonisolated at entry (SE-0327) |

The asymmetry matters: **nonisolated → isolated is free.** The common shape — isolated things depending on nonisolated things — costs nothing. The expensive direction, a nonisolated provider depending on a `@MainActor` one, is surfaced as `async` rather than hidden.

### What the compiler needs from you

- **SE-0411, for same-domain isolated dependencies only.** Zerk puts a resolved dependency in a default argument, which relies on SE-0411 evaluating it in the callee's isolation domain. Swift 6 language mode has this always; a Swift 5 target needs `SWIFT_UPCOMING_FEATURE_ISOLATED_DEFAULT_VALUES` or complete strict concurrency (see [Requirements](#consuming-targets-in-swift-5-language-mode)). Zerk refuses only this construct, and only when `ZerkSettings.json` says the target lacks it.
- **`ZerkSettings.json`.** A build-tool plugin cannot read `SWIFT_DEFAULT_ACTOR_ISOLATION`, so you restate it (see below). Without it Zerk assumes `nonisolated`.

### Under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`

With that setting, a declaration that states no isolation of its own *is* `@MainActor` — including your `@Injectable` types. Zerk mirrors that, so most of the generated registry becomes `@MainActor`-isolated. That is what the flag means; the point is to make it explicit rather than accidental. If you want DI callable from anywhere, mark the provider `nonisolated`:

```swift
@Injectable<ApiServicing>
final class ApiService: ApiServicing {
    nonisolated init(baseURL: String) { ... }   // Zerk<ApiServicing>.inject() stays nonisolated
}
```

### Effectful and cross-domain dependencies

`await` cannot appear in a default argument at all. So a dependency whose resolution is effectful or crosses a domain is not exposed as a defaulted parameter — the member splits in two:

```swift
// explicit variant — carries the interjection guard and the construction
nonisolated static func userRepository(manager: ApiManager) -> UserRepository { ... }

// resolving variant — resolves and delegates, inheriting the merged effects
nonisolated static func userRepository() async -> UserRepository {
    userRepository(manager: await Zerk<ApiManager>.inject())
}
```

Their arities always differ, so the overload is never ambiguous, and there is still exactly one construction point and one interjection guard per provider.

### Crossing a domain

A value that leaves the domain it was built in currently needs its key to be `Sendable` — which for `actor` injectables and `Sendable`-refined protocols it usually already is:

```swift
protocol ApiServicing: Sendable { ... }   // actors conform automatically
```

`sending` returns would remove that requirement for freshly constructed values. They are designed but deliberately not emitted yet: eligibility is computed in the codegen and the annotation withheld, because `sending` is not expressible on a property and would force every isolated argument-free provider to change shape. See `isSendingEligible` in `GeneratorOutputBuilder.swift`, which documents the full rationale.

### Singletons

Shared instances live in a generated `private enum _$zerk_singletons`, one stored property per singleton *type*, and each `Zerk<Key>` member is a getter reading from it:

```swift
private enum _$zerk_singletons {
    nonisolated(unsafe) static let store: Store = Store()
}

extension Zerk<Reading> {
    nonisolated static var store: Reading { _$zerk_singletons.store }
}

extension Zerk<Writing> {
    nonisolated static var store: Writing { _$zerk_singletons.store }
}
```

Storage sits there rather than on `Zerk<Key>` because `Zerk<Reading>` and `Zerk<Writing>` are distinct generic specializations with distinct static storage — a singleton held on them directly would exist once *per key*, so `@Singleton` would only hold within a key. Two consequences follow:

- The storage is typed as the provider's declared return type, falling back to the concrete type for an initializer. One instance serves every key, so a multi-key singleton's factory must return the concrete type; a single-key singleton's factory may return the key.
- A singleton must resolve to the same provider for every key it claims. Naming a different factory per key is a build error.

`@Singleton` storage mirrors provider isolation too: `nonisolated(unsafe) static let` for a nonisolated provider, `@MainActor static let` for a `@MainActor` one (global-actor isolation already protects the storage, so no `unsafe` escape hatch is needed). Singletons stay synchronous and non-throwing, so a singleton whose dependency lives in a *different* domain is a build error — resolving it would need `await`, and a `static let` initializer cannot.

Because the storage is shared but the `Interjecting<Key>` protocols are per key, the interjection guard lives in the getter rather than in the storage initializer. A test double is therefore consulted on every read — one installed after the first resolution still takes effect, and interjecting a singleton never builds the real instance at all.

When a singleton is injected across an isolation boundary, Zerk emits a `Sendable` constraint check next to an explanatory comment. Zerk does not attempt to prove `Sendable` from syntax; the check costs nothing when the type already conforms, and it puts the compiler's complaint on a line that explains itself.

## Settings

`ZerkSettings.json`, in your target's directory or at the package root (the target wins). The plugin declares it as a build input, so edits trigger regeneration. `//` and `/* */` comments are supported. Every key is optional; the defaults below describe a stock Swift 6 target.

```jsonc
{
  "version": 1,

  // Must match SWIFT_DEFAULT_ACTOR_ISOLATION. If the two disagree, Zerk infers
  // the wrong isolation and the generated code will not compile.
  //   "nonisolated" | "MainActor" | any custom global actor name
  "defaultActorIsolation": "nonisolated",

  // How @Injectable values reach their value when the declaration does not say.
  // Mirrors no build setting — it is Zerk's own default, overridden per value
  // by @Injectable(.copied) / @Injectable(.referenced).
  //   "copied" | "referenced"
  "valueInjectionMethod": "copied",

  // Language mode, mirroring SWIFT_VERSION — not the toolchain version.
  //   "5" | "6"
  "swiftVersion": "6",

  // Mirrors SWIFT_STRICT_CONCURRENCY. Only consulted under "5"; Swift 6
  // language mode is complete checking by definition.
  //   "minimal" | "targeted" | "complete"
  "strictConcurrency": "minimal",

  // Mirrors SWIFT_UPCOMING_FEATURE_ISOLATED_DEFAULT_VALUES (SE-0411).
  // Under "5", either this or "strictConcurrency": "complete" is what allows
  // an isolated provider to resolve a same-domain isolated dependency.
  "isolatedDefaultValues": false
}
```

The file governs how Zerk **reads** your source. It never governs what Zerk **writes** — every generated member is pinned with explicit isolation regardless.

## Limitations

**Syntax-level resolution.** The codegen parses source; it does not type-check.

Spellings Swift treats as one type *are* unified into one key, because that much is decidable from syntax: `[T]`/`Array<T>`, `[K: V]`/`Dictionary<K, V>`, `T?`/`T!`/`Optional<T>`, `()`/`Void`, `(T)`/`T`, `A & B`/`B & A`, and `P`/`any P`. Canonicalization nests, so `[String]?` and `Optional<Array<String>>` are the same key.

What it cannot unify needs real type resolution, and stays distinct: module qualification (`ModuleA.Service` vs `Service`), and any `typealias` you have not marked with `@ZerkAlias` — the plugin cannot see through an alias on its own, which is exactly why that macro exists. A provider parameter like `seed: Int` is likewise indistinguishable from an injectable dependency except by whether a matching injectable exists.

`any` is a special case. Zerk cannot tell a protocol from a superclass or a struct, and `any` is only legal on an existential — so keys *match* with `any` stripped, but the generated file emits the spelling you wrote. If one declaration says `P` and another `any P`, they are one key and `any P` is what gets emitted.

**Module-scoped.** Auto-resolution only sees the current module. `@Shared` makes a key's `inject()` public so another module can call it manually, but the consuming module cannot auto-resolve a foreign key: its plugin has no way to know that key's effects or isolation. Forward it explicitly with an `@Injectable` value if you want it in the graph.

**Conformances must be written on the declaration.** `@Injectable<Key>` checks that the type lists `Key` in its own inheritance clause. A conformance added in an extension, inherited transitively, or declared in another module is invisible to a syntax-only plugin.

**Global actor detection is heuristic.** `@MainActor` is recognized exactly; any other attribute ending in `Actor` is assumed to be a global actor. A custom global actor named otherwise, or isolation inherited through a conformance, is invisible to the plugin — annotate it with `@Isolated<A>`.

**Ambient isolation is restated, not read.** The plugin cannot see `SWIFT_DEFAULT_ACTOR_ISOLATION`, so `ZerkSettings.json` has to agree with it. When they disagree Zerk infers the wrong provider isolation and the generated code fails to compile. The failure is loud and immediate, but the file is load-bearing rather than advisory.

**`@Isolated<A>` is unverified.** It states what the compiler already believes; Zerk cannot check that claim and will generate code matching whatever you wrote.

**A key may have many providers; exactly one of them backs `inject()`.** When several types claim a key, one needs `@Injectable(primary: true)`. When the winning type has several providers for that key, one needs `@InjectableProviding(primary: true)`. Unresolved ambiguity is a build error — but only for the type that actually wins the key; a losing type's providers are just named members and need no primary.

**Circular dependencies are rejected** with the cycle path in the error. Break cycles manually (e.g. inject a factory or make one edge parametric).

**Generated member names must be unique per key *per signature*.** Providers may share a member name when their parameters differ — two marked initializers both generate `Zerk<Key>.loader(...)`, told apart exactly as the initializers are. Two that agree on name *and* parameters (e.g. a `Service` in two files, both argument-free) collide; rename the type or use a distinctly named `@InjectableProviding` factory.

**`@Singleton` constraints.** Reference types only; provider must be synchronous and non-throwing; no external arguments; no dependency in a different isolation domain, since resolving one would need `await`; exactly one provider per key, and the *same* provider across every key the type claims. A singleton injectable under several keys must be built by an initializer or by a factory returning the concrete type — its one instance is stored once and read through every key.

**Referenced values must be visible to the generated file.** That file is a separate file in the same module, so `private` and `fileprivate` sources cannot be referenced — only copied. A mutable `static var` also has to be legal Swift 6 global state in its own right (`nonisolated(unsafe)`, or actor-isolated); Zerk mirrors whatever isolation you give it but does not launder it.

**`@Injected` cannot resolve async, throwing, or cross-domain chains** — use `try await Zerk<Key>.inject()` manually (or an `@injected` parameter). For lazy resolution, use a plain `lazy var = Zerk<Key>.inject()`; there is no `@LazyInjected` macro.

**Interjection is keyed by generated member name.** A test override conforms `Zerk` to `Interjecting<Key>` and implements `interjected<MemberName>`. Renaming an injectable type or `@InjectableProviding` factory changes that member name, so a stale conformance becomes a *compile error* — the mismatch is caught, not silently ignored. Requirements mirror the member's isolation, so a double for a `@MainActor` provider is built on the main actor.

**Interjection does not short-circuit resolution.** A member's dependencies are resolved before the guard runs, so an interjected value still builds its real dependency subtree first.

**Generated code is per-build.** The plugin output lives in the build directory (`ZerkGenerated/ZerkInjections.swift`). Never edit it; regenerate by building.

## Diagnostics

All resolution errors surface at build time with source locations, pointing at your declaration rather than at generated code. Diagnostics accumulate across the whole run, so one build reports every problem instead of only the first.

The ones you are most likely to meet: no provider found for a key, several providers for a key with none marked primary, several types claiming a key with none marked primary, more than one primary for a key, `@Singleton` on a value type / with effects / with external arguments / with a cross-domain dependency / with different providers for different keys / multi-key with a factory returning a key rather than the concrete type, circular dependency, member-name collision, `@ZerkAlias` on a non-typealias or a generic typealias, `#ZerkAlias` with fewer than two distinct types, `@Shared` on a non-public key (warning), `@Injected` on an async, throwing, or cross-domain chain, `@Isolated<A>` contradicting a `nonisolated` modifier or a global-actor attribute, and — under Swift 5 language mode without an SE-0411 opt-in — an isolated provider resolving a same-domain isolated dependency.

One diagnostic comes from the compiler rather than Zerk: a non-`Sendable` `@Singleton` injected across an isolation boundary. Zerk emits a `Sendable` constraint check with an explanatory comment so the failure lands somewhere legible instead of inside a factory body.

## Contributing

The package builds with `swift build`. To run the tests:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

The `DEVELOPER_DIR` prefix is needed when `xcode-select` points at the Command Line Tools, whose swift-testing install is incomplete; a bare `swift test` then fails to launch with a missing `Testing` module or `lib_TestingInterop.dylib`.

Isolation and effects cannot be verified by comparing generated strings — text can look right and still not compile. `Tests/ZerkInjectionCodegenTests` therefore includes a compile harness that runs the codegen over a fixture and type-checks the result with a real `swiftc`, across both language modes and both `SWIFT_DEFAULT_ACTOR_ISOLATION` values. Add a case there for anything touching isolation, effects, or `sending`.

## License

See [LICENSE](LICENSE).
