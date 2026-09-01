# Zerk documentation

Zerk is a compile-time dependency injection framework for Swift: macros make your
declarations legible to a build-tool plugin, the plugin resolves the graph during the
build, and the result is plain static factory code on a `Zerk<Key>` namespace.

If you are new, read [Installation](Getting%20Started/Installation.md) and
[Quick start](Getting%20Started/QuickStart.md), then
[Terminology](Getting%20Started/Terminology.md) — the rest of the documentation assumes
that vocabulary.

---

## Getting started

| Page | What it covers |
|---|---|
| [Installation](Getting%20Started/Installation.md) | Requirements, Swift Package Manager setup, which targets need the plugin, and Swift 5 language mode |
| [Quick start](Getting%20Started/QuickStart.md) | A value, an injectable, a consumer — and the code the plugin generates for them |
| [Terminology](Getting%20Started/Terminology.md) | Key, injectable, value, provider, primary, member, interjection point, scope |
| [Declaring — examples](Getting%20Started/InjectableExamples.md) | Worked examples of registering things, each with its real generated output |
| [Consuming — examples](Getting%20Started/InjectedExamples.md) | Worked examples of resolving things, each with its real generated output |
| [Migration from 1.x](Getting%20Started/Migration.md) | What changed, and a module-at-a-time migration path |

## Macros and markers

Every attribute and freestanding macro Zerk vends, except the testing ones.

| Page | Covers |
|---|---|
| [`@Injectable`](Macros%20and%20Markers/Injectable.md) | Registering a type — or a declaration that produces one. Keys, `primary:`, `public:`, `typeNamed:`, `name:` |
| [`@InjectableProviding`](Macros%20and%20Markers/InjectableProviding.md) | Marking how a key is built. Provider inference, `primary:`, and naming the generated member |
| [`@InjectableValue`](Macros%20and%20Markers/InjectableValue.md) | Values, `@InjectableValues` sweeps, `@NonInjectable`, copied vs referenced, and effectful values |
| [`@Singleton`](Macros%20and%20Markers/Singleton.md) | One instance per type, the generated storage, and why it lives where it does |
| [`@Scoped`](Macros%20and%20Markers/Scoped.md) | One instance per named scope, `Zerk.reset(_:)`, and the staleness checks |
| [`@Isolated`](Macros%20and%20Markers/Isolated.md) | Telling Zerk about isolation it cannot see |
| [`@Injected`](Macros%20and%20Markers/Injected.md) | The property macro — every variant, `@InjectedDynamically`, and the one macro that generates code |
| [Parameter markers](Macros%20and%20Markers/ParameterMarkers.md) | The four lowercase wrappers: `@injected`, `@autoinjected`, `@noninjected`, `@injectable` |
| [Imported injectables](Macros%20and%20Markers/ImportedInjectables.md) | `@ImportedInjectable`, `@ImportedInjectableValue` — reaching another module's graph |
| [Key aliases](Macros%20and%20Markers/InjectableAlias.md) | `@InjectableAlias` and `#InjectableAlias<A, B>()` — telling Zerk two names are one key |

## Features

Topics that span several macros.

| Page | Covers |
|---|---|
| [Foreign types](Features/ForeignTypes.md) | Registering a type you do not declare — `URLSession`, a vendor SDK's client |
| [Generics](Features/Generics.md) | The three ways to register a generic type, and what each can do |
| [Concurrency](Features/Concurrency.md) | Isolation, effects, crossing a domain, and what Swift 6 needs from you |
| [Conditional compilation](Features/ConditionalCompilation.md) | `#if` around registrations — carrying the guard into generated code, and per-configuration primaries |
| [SwiftUI and `@Observable`](Features/SwiftUI.md) | `@ObservationIgnored`, property wrappers, and registering a view model |

## The plugin

How code generation works, and what it produces.

| Page | Covers |
|---|---|
| [How it works](Plugin/HowItWorks.md) | Macros vs plugin, the three stages, and why the plugin reads syntax and never resolved types |
| [Generated code](Plugin/GeneratedCode.md) | An annotated tour of what the plugin emits, construct by construct |
| [Settings](Plugin/Settings.md) | `ZerkSettings.json` — every key, its meaning, and its default |
| [Diagnostics](Plugin/Diagnostics.md) | Every build error and warning Zerk reports, grouped, with its fix |
| [Graph artifact](Plugin/GraphArtifact.md) | `Zerk.graph.json` — the resolved graph as data, per module and across module boundaries |
| [`ZerkCLI`](Plugin/ZerkCLI.md) | `swift package zerk` — the command plugin, its commands, options and exit codes |
| [Limitations](Plugin/Limitations.md) | What syntax-level resolution can and cannot do |

## Testing

| Page | Covers |
|---|---|
| [Interjection](Testing/Interjection.md) | What an interjection point is, how it is named, and how `#Interject` uses it |
| [Scopes](Testing/Scopes.md) | The `.zerk` trait, reusable interjection sets, XCTest, and SwiftUI previews |
| [Examples](Testing/Examples.md) | Worked testing examples, from the minimal case to generic keys and parallel suites |

---

## Finding things quickly

**"How do I register …"**

| a type | [`@Injectable`](Macros%20and%20Markers/Injectable.md) |
|---|---|
| a constant or configuration value | [`@InjectableValue`](Macros%20and%20Markers/InjectableValue.md) |
| a type from another module | [Foreign types](Features/ForeignTypes.md) |
| a generic type | [Generics](Features/Generics.md) |
| a key another module owns | [Imported injectables](Macros%20and%20Markers/ImportedInjectables.md) |

**"How do I resolve …"**

| into a property | [`@Injected`](Macros%20and%20Markers/Injected.md) |
|---|---|
| into an initializer or method parameter | [Parameter markers](Macros%20and%20Markers/ParameterMarkers.md) |
| by hand, or when the chain is `async`/`throws` | [`@Injected`](Macros%20and%20Markers/Injected.md) and [Concurrency](Features/Concurrency.md) |
| lazily | [`@Injected`](Macros%20and%20Markers/Injected.md) |
| afresh on every access | [`@InjectedDynamically`](Macros%20and%20Markers/Injected.md#injecteddynamically) |

**"How do I swap an implementation per build configuration?"** —
[Conditional compilation](Features/ConditionalCompilation.md).

**"How long does an instance live?"** — one resolution by default;
[`@Scoped`](Macros%20and%20Markers/Scoped.md) until its scope is reset;
[`@Singleton`](Macros%20and%20Markers/Singleton.md) for the process.

**"The build failed"** — [Diagnostics](Plugin/Diagnostics.md), then
[Limitations](Plugin/Limitations.md).

**"I want a test double"** — [Interjection](Testing/Interjection.md), then
[Examples](Testing/Examples.md).

---

[Changelog](../CHANGELOG.md) · [← Back to the README](../README.md)
