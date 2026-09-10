# Migrating from Zerk 1.x

What Zerk 2 replaced, and the order to replace it in. Each step links to the page that explains it in depth.

## What's changed

Zerk 2 is a ground-up replacement for the original runtime container:

- Dependency registration moved from runtime calls like `Zerk.store.singleton(...)` to source annotations read by `ZerkPlugin`.
- Resolution moved from `Zerk.standardStorage.restore()` to generated members on `Zerk<Key>`, usually reached through `Zerk<Key>.inject()` or `@Injected`.
- Missing providers, ambiguous providers, cycles, unsupported singletons, and isolation mismatches are reported during the build instead of failing at runtime.
- Swift concurrency is modeled directly: generated injectors mirror provider isolation, propagate `async`/`throws`, and reject constructs that Swift cannot express safely.
- Test overrides are compile-checked and scoped per test, rather than mutating a shared container.
- Lifetimes are annotations rather than registration chains: transient by default, [`@Scoped`](../Macros%20and%20Markers/Scoped.md) for one instance per named scope, [`@Singleton`](../Macros%20and%20Markers/Singleton.md) for one per process.
- Installation is Swift Package Manager only; CocoaPods-era runtime APIs and key-path property injection wrappers are no longer part of the public model.

## Changes in 2.1

Two things a 2.0 module has to be updated for. Both are compiler errors rather than silent
behaviour changes, so the build tells you where.

- **`#ZerkImport(module:)` is gone.** The generated file now takes its imports from the files it
  reads — every module imported by a file that names a type from outside this one. Delete the
  declarations; nothing replaces them. See
  [Imported injectables](../Macros%20and%20Markers/ImportedInjectables.md).
- **`@ZerkAlias` and `#ZerkAlias<A, B>()` are `@InjectableAlias` and `#InjectableAlias<A, B>()`.**
  A rename only — the behaviour is unchanged. It leaves no macro with `Zerk` in its name, so the
  whole set now reads the same way. See
  [Key aliases](../Macros%20and%20Markers/InjectableAlias.md).

## Migrating a module

For an app using Zerk 1.x, migrate one module at a time:

1. Replace the dependency with [Swift Package Manager](Installation.md) and attach `ZerkPlugin` to each target that declares injectable types or values. Remove CocoaPods integration for Zerk.
2. Delete central registration code (`Zerk.store`, `AutoStoring`, `transient`, `scoped`, and `singleton` chains). [The graph now comes from declarations in the source files themselves.](../Plugin/HowItWorks.md)
3. Mark injectable implementations with [`@Injectable`](../Macros%20and%20Markers/Injectable.md) or `@Injectable<Protocol>`, then pick a lifetime. Unmarked is transient — a new instance per resolution — and is the right default. [`@Singleton`](../Macros%20and%20Markers/Singleton.md) is the old singleton lifetime. [`@Scoped(.name)`](../Macros%20and%20Markers/Scoped.md) is new in 2.x: one instance kept until `Zerk.reset(.name)` drops it, which is what a 1.x `scoped` chain was most likely reaching for. Check the mapping against what that scope meant in your app rather than assuming — 2.x scopes are named values reset explicitly, not tied to any object's lifetime.

   A consumer that outlives the scope it depends on needs [`@InjectedDynamically`](../Macros%20and%20Markers/Injected.md#injecteddynamically) rather than `@Injected`, since a reset cannot reach a reference already handed out. Zerk makes the worst case — a `@Singleton` capturing a scoped instance — a build error.
4. Mark each initializer or static factory Zerk may call with [`@InjectableProviding`](../Macros%20and%20Markers/InjectableProviding.md). If there is exactly one initializer and no provider is marked, Zerk infers it. A key with several providers needs one of them marked `@InjectableProviding(primary: true)`.
5. Convert registered constants or configuration values into [`@InjectableValue`](../Macros%20and%20Markers/InjectableValue.md) declarations, or group static members under `@InjectableValues`. Note that values have their own marker: `@Injectable` registers a *type*.
6. Replace manual restores with [`Zerk<Key>.inject()`](../Plugin/GeneratedCode.md). Replace property injection with [`@Injected var dependency: Key`](../Macros%20and%20Markers/Injected.md) when the dependency can be resolved synchronously.
7. For initializer or method parameters that should be filled automatically, use lowercase [`@injected`](../Macros%20and%20Markers/ParameterMarkers.md) on the parameter and call the generated overload.
8. Move tests from container mutation to [interjection](../Testing/Interjection.md): `@testable import` the declaring module, put `.zerk` on the suite, and call `#Interject` for what you want to stand in.
9. Add [`ZerkSettings.json`](../Plugin/Settings.md) if your target uses Swift 5 language mode, `SWIFT_DEFAULT_ACTOR_ISOLATION`, or a non-default value injection policy.

## Wrappers with no 2.x equivalent

Key-path wrappers from 1.x such as `@InjectedProperty`, `@InjectedMutableProperty`, and `@InjectedMethod` do not have direct 2.x equivalents. Inject the dependency itself, or expose the needed operation through a small protocol and inject that protocol.

---

[← Table of contents](../TableOfContents.md)

**See also:** [Installation](Installation.md) · [Quick start](QuickStart.md) · [Terminology](Terminology.md) · [Injectable](../Macros%20and%20Markers/Injectable.md) · [Interjection](../Testing/Interjection.md)
