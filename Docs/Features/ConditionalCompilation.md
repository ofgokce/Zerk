# Conditional compilation

Registering different implementations per build configuration — `#if DEBUG` / `#else`, `#if os(iOS)`, a feature flag — and what Zerk does with the conditions.

The short version: **Zerk carries your conditions into the generated file.** A type registered inside `#if DEBUG` generates code inside `#if DEBUG`, and registrations in different clauses of one `#if` are alternatives rather than rivals.

## The shape this is for

```swift
protocol Service {}

#if DEBUG
@Injectable<Service>(primary: true)
struct DebugService: Service {
    let logging: Logging
}
#else
@Injectable<Service>(primary: true)
struct ReleaseService: Service {
    let logging: Logging
}
#endif

@Injectable
struct App {
    let service: Service
}
```

Two types claim `Service`, both primary — which anywhere else would be
`Multiple primary injectables found for 'Service'`. Here it is not, because no build sees both. Zerk elects a primary **per configuration** and emits one `inject()` for each:

```swift
extension Zerk<Service> {
#if (DEBUG)
    nonisolated static func debugService(logging: Logging = Zerk<Logging>.inject()) -> Service {
        …
        return DebugService(logging: logging)
    }
#endif

#if !(DEBUG)
    nonisolated static func releaseService(logging: Logging = Zerk<Logging>.inject()) -> Service {
        …
        return ReleaseService(logging: logging)
    }
#endif

#if (DEBUG)
    nonisolated static func inject() -> Service {
        debugService()
    }
#endif

#if !(DEBUG)
    nonisolated static func inject() -> Service {
        releaseService()
    }
#endif
}
```

`App` is unconditional, so its member is too — and it resolves the key through the same `Zerk<Service>.inject()` call in every configuration:

```swift
nonisolated static func app(service: Service = Zerk<Service>.inject()) -> App { … }
```

## Why the conditions are carried rather than evaluated

Zerk never decides whether `DEBUG` holds. It cannot, for two independent reasons:

- A build-tool plugin is handed the package, a work directory and its tools. `PluginContext` carries no build configuration and no active compilation conditions.
- Even a settings file could not stand in, the way [`ZerkSettings.json`](../Plugin/Settings.md) does for ambient isolation. `DEBUG` differs between two builds of the *same* target from one file on disk — and SwiftPM caches a plugin's result across configurations, so an answer baked in during a Debug build would be reused verbatim for the Release one.

Reproducing the guard hands the decision back to the compiler, which has the knowledge Zerk lacks. One generated file is correct in every configuration.

## A key that exists in one configuration only

```swift
#if DEBUG
@Injectable
struct DebugOnlyTool {}
#endif
```

The generated extension names `DebugOnlyTool`, so the guard goes **outside** it:

```swift
#if (DEBUG)
extension Zerk<DebugOnlyTool> {
    nonisolated static var debugOnlyTool: DebugOnlyTool { … }

    nonisolated static func inject() -> DebugOnlyTool {
        debugOnlyTool
    }
}
#endif
```

A Release build neither builds the member nor names the type.

Note what this means for consumers: in a configuration where the key has no provider, `Zerk<DebugOnlyTool>.inject()` does not exist, and anything resolving it does not compile. That is the honest outcome — the dependency really is absent — but it is worth writing the `#else` branch rather than discovering it in a Release build.

## `#elseif` and nesting

An `#elseif` clause is only active when every earlier condition failed, so its guard carries those failures:

```swift
#if DEBUG          →  #if (DEBUG)
#elseif BETA       →  #if !(DEBUG) && (BETA)
#else              →  #if !(DEBUG) && !(BETA)
```

Nested `#if`s become one conjunction rather than nested blocks:

```swift
#if DEBUG
#if os(iOS)
@Injectable
struct Probe {}
#endif
#endif
```
```swift
#if (DEBUG) && (os(iOS))
extension Zerk<Probe> { … }
#endif
```

Every condition is parenthesised before it is combined, so a condition of your own like `A || B` keeps its meaning under the surrounding `&&`.

## What carries a guard

Everything Zerk generates for a conditional declaration:

| Written inside a `#if` | What gets guarded |
|---|---|
| `@Injectable` type or declaration | Its member, its `inject()`, its interjection point — and the whole `extension Zerk<Key>` when every provider of that key shares the condition |
| `@InjectableValue` | Its member's extension and its interjection point |
| `@Singleton` / `@Scoped` | Its slot in the generated storage namespace |
| `@injected` parameter markers | The generated overload, and its `extension YourType` |
| `#ZerkImport(module:)` | The `import` line. Asked for under two *different* conditions, it is emitted unconditionally: the wider ask wins, because an unnecessary import is a warning at worst while a missing one does not compile |

The [graph artifact](../Plugin/GraphArtifact.md) records the guard too: each provider carries a `condition` field with the expression its member is emitted under, absent when unconditional. A graph that omitted it would claim a key is resolvable in builds where nothing resolves it.

## What Zerk will not infer

**Two separate `#if`s are never treated as exclusive.**

```swift
#if DEBUG
@Injectable<Service>(primary: true)
struct DebugService: Service {}
#endif

#if !DEBUG                          // ← a different #if
@Injectable<Service>(primary: true)
struct ReleaseService: Service {}
#endif
```

To a reader these are opposites. Proving it means evaluating `DEBUG`, which Zerk cannot do — so this is `Multiple primary injectables found for 'Service'`, and the fix is to write it as one `#if` / `#else`.

The asymmetry is deliberate. Wrongly deciding two registrations are exclusive would silence a real ambiguity and pick a provider arbitrarily; wrongly deciding they can coexist only asks you to write `#else`, and says so.

## Two refusals

### The branches must agree on what resolving costs

Everything that injects a key resolves it through a single `Zerk<Key>.inject()` call, emitted once for every configuration. So the branches may differ in *what they build* — that is the point — but not in the effects, the isolation, or the arguments left to the caller:

```swift
#if DEBUG
@Injectable<Service>(primary: true)
struct DebugService: Service {}
#else
@MainActor                              // ← resolves in a different domain
@Injectable<Service>(primary: true)
final class ReleaseService: Service {}
#endif
```

> `'ReleaseService' and 'DebugService' both resolve 'Service', in different branches of one #if, but they resolve in different isolation domains (nonisolated versus @MainActor). …`

Make the branches match, or give them separate keys.

### A `#if` inside a type may not gate what Zerk reads off its members

```swift
@Injectable
struct Service {
    #if DEBUG
    init(dep: Dep) {}
    #else
    init() {}
    #endif
}
```

One type, two provider shapes — and the generated member has a single signature. Put the `#if` around the whole type instead, so each configuration declares its own.

Zerk reads a type's members without expanding conditions, so four things trigger this, and they are four ways the same mistake shows up:

| Inside a `#if` | Why it cannot be carried |
|---|---|
| an initializer | two provider shapes, one member signature |
| an `@InjectableProviding` member | the same |
| a **stored property that would be a required parameter** | a struct's memberwise initializer is shaped by them, so a conditional one silently vanishes from the parameters Zerk thinks exist — and it emits a call missing an argument. Only *required* ones count: a property with a value of its own, a computed one, or one carrying `@Injected`/`@InjectedDynamically` is not asked for either way. Nor does any of this apply once the type declares its own initializer or an `@InjectableProviding` member, since inference is then never consulted |
| a member with **`@injected` parameters** | its generated overload is assembled from the member list too, so the member was being dropped without a word |

It applies inside an `extension` too, where the same members are read the same way.

The refusal stays narrow. A `#if` gating something Zerk does not read — a conditional method with no markers, a computed property, a debug-only helper, a `#if` around an import — is none of Zerk's business and passes through untouched.

---

[← Concurrency](Concurrency.md) · [Diagnostics →](../Plugin/Diagnostics.md) · [Back to contents](../TableOfContents.md)
