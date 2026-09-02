# Changelog

Every released version of Zerk, newest first, starting at 1.0.0. Dates are the release's
commit date.

Zerk follows semantic versioning: a major version is a breaking change, a minor version adds to
what is already there, a patch fixes it. There are two majors because Zerk was rebuilt once:
`1.x` was a runtime container, and `2.x` resolves the graph at build time instead.

---

## 2.1.0 — 2026-09-02

Naming and name resolution. Every change here is a compiler error rather than a silent behaviour
change, so the build says where. See [Changes in 2.1](Docs/Getting%20Started/Migration.md).

### Removed

- **`#ZerkImport(module:)`.** The generated file now takes its imports from the files it reads:
  every module imported by a file that names a type from outside this one. Restating them by hand
  was the part that could be forgotten, and forgetting it was a build failure in generated code.
  Delete the declarations; nothing replaces them.

### Renamed

- **`@ZerkAlias` and `#ZerkAlias<A, B>()` are now `@InjectableAlias` and
  `#InjectableAlias<A, B>()`.** Behaviour is unchanged. No macro carries `Zerk` in its name any
  more, so the whole set reads the same way.
- The documented namespace for imported declarations is spelled `ImportedInjectables` rather than
  `ZerkImports` throughout the examples. It is a name you choose — Zerk never reads it — so
  nothing breaks either way.

### Fixed

- **A key's name is now read in the scope it was written in.** Swift looks a bare type name up
  innermost-first, and the generated file lives at file scope, so the two disagreed for anything
  nested: `init(config: Config)` inside `LiveFeed` emitted `config: Config`, which fails to
  compile as `cannot find type 'Config' in scope`. The name is now qualified —
  `config: LiveFeed.Config` — with only the base of a dotted path moving, since that is the part
  Swift looks up. Where the bare name also existed at file scope, Zerk had been matching the
  wrong key and running its effect and conditional-compilation checks against the wrong provider.
- **Two imported keys sharing a bare name stay two keys.** `ModuleA.Config` and `ModuleB.Config`
  were merged and then reported as `'Config' is imported more than once`, against two imports
  naming different types.
- **A local declaration shadows an imported name of the same spelling.** A module declaring
  `Serving` and importing a `Core.Serving` was told the key was `both imported and declared` —
  for source Swift compiles as written, where the local declaration simply shadows the import.
- **A type named after a module is no longer read as a module qualifier.** Declaring `Core`
  shadows the module everywhere in that module, so `Core.Serving` names that type's member;
  stripping the qualifier emitted an extension over a different type than the call site used.
- **`@Injected` on a property of an `@Observable` type** reported `a global has no such moment`,
  naming storage the developer never wrote. It now names the problem and the fix: mark the
  property `@ObservationIgnored`, which leaves it stored.
- **`@Injected` alongside a property wrapper** produced only the compiler's
  `init accessor cannot refer to property`, which mentions neither the wrapper nor Zerk. It now
  names the wrapper and the spelling that works —
  `@StateObject var model = Zerk<Key>.inject()`.

### Added

- **`swift package zerk settings`** — writes `ZerkSettings.json` from an Xcode target's build
  settings instead of from memory. The plugin API cannot read build settings, which is why the
  file exists at all; `xcodebuild -showBuildSettings` can, so this maps its answer onto the four
  keys that mirror one and leaves `valueInjectionMethod`, which mirrors nothing, alone. A setting
  the target does not set is left out, so Zerk's default applies. Needs Xcode. See
  [`zerk settings`](Docs/Plugin/ZerkCLI.md#zerk-settings).

### Changed

- **`swift-tools-version` is 6.2**, up from 6.1. It was never the real floor: a Swift 6.2
  toolchain has always been required, because interjection points are named with raw identifiers
  (SE-0451) that land in the generated file your toolchain compiles. The manifest now says so, so
  an older SwiftPM refuses it up front instead of failing later inside generated code.
- **`ZerkSettings.json` is decoded rather than deserialized and cast.** The type guards used to
  read a `JSONSerialization` `Any`, where a JSON boolean and a JSON number are indistinguishable
  in both directions — `true as? Int` is `1` and `1 as? Bool` is `true` — so telling them apart
  needed `CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID()`. `JSONDecoder` draws the
  distinction in the language instead, and the messages for a malformed key are unchanged.
- That was also the one thing in Zerk only Darwin could answer, so the package now has no
  Apple-only dependency outside `#if canImport` guards. CI builds and tests it on Linux.

### Documentation

- New [SwiftUI and `@Observable`](Docs/Features/SwiftUI.md) page: `@ObservationIgnored`, property
  wrappers, and registering a view model.
- New "Storage a property does not have" section in
  [Diagnostics](Docs/Plugin/Diagnostics.md), covering all four cases where `@Injected` has no
  storage to initialize.
- A "Changes in 2.1" section in [Migration](Docs/Getting%20Started/Migration.md).
- This file.

---

## 2.0.0 — 2026-08-19

A ground-up replacement. Zerk stopped being a runtime container and became a build-time code
generator: macros make declarations legible, a Swift Package Manager build-tool plugin resolves
the graph during the build, and the output is plain static factory code on a `Zerk<Key>`
namespace. Nothing from 1.x carries over — see
[Migrating from Zerk 1.x](Docs/Getting%20Started/Migration.md).

### Added

- **Registration by annotation.** `@Injectable`, `@InjectableProviding`, `@InjectableValue`,
  `@InjectableValues`, `@NonInjectable`, replacing runtime calls like
  `Zerk.store.singleton(...)`.
- **Lifetimes as annotations.** Transient by default, `@Scoped` for one instance per named scope,
  `@Singleton` for one per process.
- **Resolution through generated members** on `Zerk<Key>`, reached as `Zerk<Key>.inject()` or
  through `@Injected` / `@InjectedDynamically`.
- **Build-time diagnostics.** Missing providers, ambiguous providers, cycles, unsupported
  singletons and isolation mismatches are reported during the build rather than trapping at
  runtime.
- **Swift concurrency modelled directly.** Generated injectors mirror provider isolation,
  propagate `async` and `throws`, and refuse constructs Swift cannot express safely. `@Isolated`
  states isolation the plugin cannot see.
- **Cross-module graphs.** `@ImportedInjectable` and `@ImportedInjectableValue` describe a key or
  value another module owns, so this module's graph can resolve against it.
- **Key aliases.** `@ZerkAlias` and `#ZerkAlias<A, B>()` tell Zerk that two names are one key.
- **Parameter markers.** `@injected`, `@autoinjected`, `@noninjected`, `@injectable`.
- **Compile-checked test overrides.** `@Interject` and the `ZerkTesting` module, scoped per test
  instead of mutating a shared container.
- **Conditional compilation.** `#if` around registrations is carried into the generated code,
  including per-configuration primaries.
- **Generics**, in three registration forms, and foreign types you do not declare.
- **`ZerkCLI`** and a **graph artifact**, so the resolved graph can be inspected and merged
  across modules.
- **`ZerkSettings.json`**, for the facts about a target that syntax cannot reveal.
- Full documentation under `Docs/`, from installation through the plugin's internals.

### Removed

- The entire 1.x runtime API: `Zerk.store`, `Zerk.standardStorage`, `Zerk.newStorage()`,
  `DependencyStorage`, the `store`/`restore` calls, `DependencyArguments`, `AutoStoring`, and the
  property-injection wrappers (`InjectedProperty`, `InjectedMutableProperty`,
  `InjectedUnwrappedProperty`, `InjectedUnwrappedMutableProperty`).
- **CocoaPods support.** `Zerk.podspec` is gone; installation is Swift Package Manager only.

### Changed

- Requires Swift tools 6.1, up from 5.5.
- Platform floor is iOS 13 / macOS 13 / tvOS 13 / watchOS 6 / visionOS 1, up from iOS 9.

---

## 1.0.5 — 2023-10-26

### Added

- Restoring an optional type. `restore()` for a `D?` now finds a dependency stored as `D`, rather
  than failing to match because the stored name did not include `Optional<…>`.

---

## 1.0.4 — 2023-10-26

### Changed

- Dependencies are keyed by the type's name rather than by `ObjectIdentifier`, so a type
  identified across module or metatype boundaries resolves to the same entry.

---

## 1.0.3 — 2023-10-04

### Changed

- `AutoStoring.store()` renamed to `autoStore()`.

---

## 1.0.2 — 2023-10-04

### Fixed

- A deadlock when auto-storing. `restore` took the storage lock and *then* ran the auto-store
  pass, which stores dependencies and so takes the same lock. The pass now runs before the lock
  is taken.

### Changed

- The multi-type storing methods changed shape: the types come first and the builder is a
  trailing argument — `transient(A.self, B.self, builder:)` rather than
  `transient(_:as:)`. Each lifetime also gained overloads for a builder taking nothing, the
  storage, or the storage and arguments.

---

## 1.0.1 — 2023-09-20

### Fixed

- `AutoStoring` was internal, so no other module could conform to it. It is now `public`.

---

## 1.0.0 — 2023-07-02

First release. A runtime dependency container: you register dependencies into a storage, and
resolve them from it by type.

### Added

- **`Zerk.store`** for registration and **`Zerk.standardStorage`** for resolution, both on a
  shared storage, with **`Zerk.newStorage()`** for an independent one.
- **Three lifetimes** — `transient`, `scoped` and `singleton`. Each takes a builder, and the
  builder's parameters are themselves resolved from the storage, so a dependency can be declared
  in terms of others: `Zerk.store.singleton { (api: Api) in Repository(api: api) }`. Overloads go
  up to ten such parameters.
- **Registering one dependency under several types** — `transient(builder, as: Repositoring.self,
  Caching.self)` — so one instance answers for every protocol it conforms to.
- **`restore()`**, resolving by the type a dependency was stored under, and
  **`restore(with:)`** for the argument form below.
- **`@Injected`**, a read-only property wrapper resolving from the standard storage, or from one
  you name along with arguments — `@Injected(from: customStorage, with: .arguments(id: 3))`.
- **Property-level wrappers**, for injecting one property of a dependency rather than the whole
  instance: `InjectedProperty`, `InjectedMutableProperty`, `InjectedUnwrappedProperty` and
  `InjectedUnwrappedMutableProperty`.
- **`DependencyArguments`**, a `@dynamicCallable` and `@dynamicMemberLookup` argument bag, so a
  builder can take values named at the call site. Names and types are checked at runtime.
- **`AutoStoring`**, so a type can register itself rather than being registered centrally. The
  protocol shipped `internal` in this version, which left it unusable from another module — see
  1.0.1.
- Installation through Swift Package Manager and CocoaPods.
- Requires Swift tools 5.5, iOS 9.
