# Installation

What Zerk needs from your toolchain, how to add the package with Swift Package Manager, and which targets the build plugin has to be attached to.

## Requirements

- Swift 6.2 **toolchain** (`swift-tools-version: 6.1`); the runtime, the macros and the macro toolkit build in `.v6` language mode, the codegen half in `.v5`
- swift-syntax 602.x
- Platforms: iOS 13+, macOS 13+, watchOS 6+, tvOS 13+, visionOS 1+, Mac Catalyst 13+

6.2 is the floor because interjection points are named with raw identifiers (SE-0451) — they appear in the generated file your toolchain compiles, and in the key paths `#Interject` expands. Your *language mode* is a separate question, answered below.

### Consuming targets in Swift 5 language mode

Your target does **not** have to be in Swift 6 language mode. A target with `SWIFT_VERSION = 5` under the Swift 6.2 toolchain above (Xcode 26 or later) is fully supported, with one exception:

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

Without one of these, Zerk emits a build error against your `ZerkSettings.json` — quoting the settings it read and listing every way to unlock it, including marking the providers `nonisolated` — rather than generating code that cannot compile. Every other isolated construct generates normally.

## Adding the package

Attach the build plugin to every target that **declares** injectables. Test targets do not need it — they reach interjection through `@testable import`, plus the `ZerkTesting` library for the `.zerk` trait:

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

## The three products

The package vends three products: the `Zerk` library (the macros and the `Zerk<Key>` namespace), the `ZerkPlugin` build-tool plugin, and `ZerkTesting` (the `ZerkInterjections` trait, spelled `.zerk` at a use site). `ZerkTesting` depends on swift-testing, so keep it to test targets:

```swift
    .testTarget(
        name: "AppTests",
        dependencies: ["App", .product(name: "ZerkTesting", package: "Zerk")]
    ),
```

## Which targets need the plugin

The plugin generates the injectors **and** each key's interjection points into the module that declares the injectables. A test target that does `@testable import App` names those points with a key path; the lookups already compiled into `App` consult the scope in force at runtime. Attach the plugin to a test target only if that target itself declares injectables (as this package's own `ZerkTests` does, because its fixtures live in the test target). In an Xcode project, add `ZerkPlugin` under the declaring target's Build Phases → Run Build Tool Plug-ins.

## Privacy manifest

The `Zerk` library ships a `PrivacyInfo.xcprivacy`, so Xcode's privacy report for your app
accounts for it without you writing anything. It declares nothing, because there is nothing
to declare:

| key | value |
|---|---|
| `NSPrivacyTracking` | `false` |
| `NSPrivacyTrackingDomains` | empty |
| `NSPrivacyCollectedDataTypes` | empty |
| `NSPrivacyAccessedAPITypes` | empty |

Zerk collects nothing, contacts nothing, and uses no [required-reason
API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
— no user defaults, file timestamps, disk space, boot time, or active keyboards. The
`ProcessInfo` it does touch is `environment`, to detect a SwiftUI preview, which is not on
that list.

`Zerk` is the only target that carries one, because it is the only target whose code reaches
your app. `ZerkPlugin`, `ZerkCodegen` and the macro plugin all run on the build machine and
are never linked into the binary; `ZerkTesting` is for test targets, which are not submitted.

One consequence worth knowing: declaring a resource makes SwiftPM emit a `Zerk_Zerk.bundle`
alongside the library. That is expected, and it is where the manifest lives.

## Build settings the plugin cannot see

The plugin reads your source syntax, not your build settings. Anything about how the compiler is configured — the language mode above, `SWIFT_DEFAULT_ACTOR_ISOLATION`, the value injection policy — is restated in a `ZerkSettings.json` placed next to your target's sources, or at the package root. The full schema is in [Settings](../Plugin/Settings.md).

---

[← Table of contents](../TableOfContents.md)

**See also:** [Quick start](QuickStart.md) · [Migration](Migration.md) · [Settings](../Plugin/Settings.md) · [How it works](../Plugin/HowItWorks.md) · [Concurrency](../Features/Concurrency.md)
