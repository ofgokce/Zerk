# Concurrency

How Zerk's generated members relate to Swift 6's isolation model: what a member's isolation is derived from, when a dependency costs an `await`, and what the compiler needs restated because a build plugin cannot read it.

## The rule

Zerk's rule is: **a generated member's isolation is its provider's isolation.** Whatever a provider is isolated to — nothing, a global actor, or an actor's nonisolated init — the member built for it says the same thing explicitly, so the generated file's meaning never depends on a build flag.

Isolation does not merge. There is no join of `MainActor` and `DatabaseActor`, so a dependency in a *different* domain does not change the member's isolation — it converts into an `async` effect instead:

| dependency | member | cost |
|---|---|---|
| nonisolated | any | none — synchronous call |
| same domain | same domain | none — synchronous call |
| domain A | domain B, or nonisolated | the member becomes `async` |
| `actor` | any | none — a sync actor init is nonisolated at entry (SE-0327) |

The asymmetry matters: **nonisolated → isolated is free.** The common shape — isolated things depending on nonisolated things — costs nothing. The expensive direction, a nonisolated provider depending on a `@MainActor` one, is surfaced as `async` rather than hidden.

## What the compiler needs from you

- **SE-0411, for same-domain isolated dependencies only.** Zerk puts a resolved dependency in a default argument, which relies on SE-0411 evaluating it in the callee's isolation domain. Swift 6 language mode has this always; a Swift 5 target needs `SWIFT_UPCOMING_FEATURE_ISOLATED_DEFAULT_VALUES` or complete strict concurrency (see [Requirements](../Getting%20Started/Installation.md#consuming-targets-in-swift-5-language-mode)). Zerk refuses only this construct, and only when `ZerkSettings.json` says the target lacks it.
- **`ZerkSettings.json`.** A build-tool plugin cannot read `SWIFT_DEFAULT_ACTOR_ISOLATION`, so you restate it (see below). Without it Zerk assumes `nonisolated`.

Isolation the plugin cannot see in your syntax at all — a custom global actor whose name does not end in `Actor`, or isolation inherited through a conformance — is restated with [`@Isolated<A>`](../Macros%20and%20Markers/Isolated.md).

## Under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`

With that setting, a declaration that states no isolation of its own *is* `@MainActor` — including your `@Injectable` types. Zerk mirrors that, so most of the generated registry becomes `@MainActor`-isolated. That is what the flag means; the point is to make it explicit rather than accidental. If you want DI callable from anywhere, mark the provider `nonisolated`:

```swift
@Injectable<ApiServicing>
final class ApiService: ApiServicing {
    nonisolated init(baseURL: String) { ... }   // Zerk<ApiServicing>.inject() stays nonisolated
}
```

The setting itself is `defaultActorIsolation` in [Settings](../Plugin/Settings.md); it must match the build setting, because if the two disagree Zerk infers the wrong isolation and the generated code will not compile.

## How a provider throws

Effects propagate up a chain and only ever widen — if anything a provider needs is `async` or throwing, the member built for it is too.

`throws` and `rethrows` are kept apart, because collapsing them is not free. Widening `rethrows` to `throws` would force `try` on a call site passing a non-throwing closure, and a `try` needs a throwing context — so the widening would climb the *caller's* stack for no reason. A `rethrows` provider keeps `rethrows`:

```swift
@Injectable
struct Mapper {
    @InjectableProviding
    init(transform: () throws -> Int) rethrows {}
}

// static func mapper(transform: () throws -> Int) rethrows -> Mapper
// static func inject(transform: () throws -> Int) rethrows -> Mapper

Zerk<Mapper>.inject(transform: { 1 })            // no `try` — the closure cannot throw
try Zerk<Mapper>.inject(transform: aThrowingOne) // `try` only where it is earned
```

It widens to `throws` in the two places it must, and both are Swift's rules rather than Zerk's:

- **Something else in the chain throws outright.** A `rethrows` provider with a dependency that `throws` yields a resolving variant that says `throws` — once anything throws unconditionally, so does the member. The explicit variant, which takes that dependency as a parameter rather than resolving it, keeps `rethrows`.
- **Nothing is left to rethrow from.** Swift requires a `rethrows` function to have a throwing function parameter. If the closure resolves from the graph, `inject()` may take no parameters at all, so it says `throws`.

A **typed** throw (`throws(MyError)`) widens to an untyped `throws`. The member would have to restate the error type, and the moment two providers in a chain name different ones there is no single type left to restate; the concrete error is still yours to catch.

## Effectful and cross-domain dependencies

`await` cannot appear in a default argument at all. So a dependency whose resolution is effectful or crosses a domain is not exposed as a defaulted parameter — the member splits in two.

Given a nonisolated provider depending on a `@MainActor` one:

```swift
@MainActor
@Injectable
final class ApiManager {
    init() {}
}

@Injectable
final class UserRepository {
    nonisolated init(manager: ApiManager) {}
}
```

Zerk emits:

```swift
// explicit variant — carries the interjection lookup and the construction
nonisolated static func userRepository(manager: ApiManager) -> UserRepository { ... }

// resolving variant — resolves and delegates, inheriting the merged effects
nonisolated static func userRepository() async -> UserRepository {
    userRepository(manager: await Zerk<ApiManager>.inject())
}
```

Their arities always differ, so the overload is never ambiguous, and there is still exactly one construction point and one interjection lookup per provider. `inject()` sits on top of the resolving variant and carries the same effects:

```swift
nonisolated static func inject() async -> UserRepository {
    await userRepository()
}
```

## Crossing a domain

A value that leaves the domain it was built in currently needs its key to be `Sendable` — which for `actor` injectables and `Sendable`-refined protocols it usually already is:

```swift
protocol ApiServicing: Sendable { ... }   // actors conform automatically
```

`sending` returns would remove that requirement for freshly constructed values. They are designed but deliberately not emitted yet: eligibility is computed in the codegen and the annotation withheld, because `sending` is not expressible on a property and would force every isolated argument-free provider to change shape. See `isSendingEligible` in `GeneratorOutputBuilder.swift`, which documents the full rationale.

## Singletons

`@Singleton` storage mirrors provider isolation the same way, and a singleton whose dependency lives in a different domain is a build error, because resolving it would need `await` and a `static let` initializer cannot. See [`@Singleton`](../Macros%20and%20Markers/Singleton.md).

---

[← Table of contents](../TableOfContents.md)

**See also:** [`@Singleton`](../Macros%20and%20Markers/Singleton.md) · [`@Isolated`](../Macros%20and%20Markers/Isolated.md) · [Settings](../Plugin/Settings.md) · [Generated code](../Plugin/GeneratedCode.md) · [Limitations](../Plugin/Limitations.md) · [Installation](../Getting%20Started/Installation.md)
