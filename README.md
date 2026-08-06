# Zerk

[![Swift Package Manager](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-brightgreen.svg?style=flat)](https://github.com/apple/swift-package-manager)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platforms](https://img.shields.io/badge/platforms-iOS%2013%2B%20%7C%20macOS%2014%2B%20%7C%20macCatalyst%2013%2B%20%7C%20watchOS%206%2B%20%7C%20tvOS%2013%2B%20%7C%20visionOS%201%2B-lightgrey.svg)](#requirements)
[![Swift Version](https://img.shields.io/badge/Swift-6.2-F16D39.svg?style=flat)](https://developer.apple.com/swift)

Zerk is a compile-time dependency injection framework for Swift. Instead of a runtime container, it combines Swift macros with a build-tool plugin that scans your module's source, resolves the dependency graph during the build, and generates plain static factory code on a `Zerk<Key>` namespace. There is nothing to register at runtime, resolution failures are build errors with file/line locations, and injected code is ordinary Swift you can step through.

For testing, the same plugin gives every generated member a named interjection point, so `#Interject` can stand a double in for any injectable — one member, or a whole key at once — without touching production code. Interjections belong to a scope, so tests keep running in parallel, and they compile to nothing in release.

Generic types are registered like any other: `@Injectable struct Cache<E>` makes `Zerk<Cache<String>>.inject()` resolve, and any specialization of it satisfies a dependency that asks for one.

## 📖 Documentation

Full documentation lives in **[Docs/](Docs/TableOfContents.md)**.

| | |
|---|---|
| **[Getting started](Docs/TableOfContents.md#getting-started)** | [Installation](Docs/Getting%20Started/Installation.md) · [Quick start](Docs/Getting%20Started/QuickStart.md) · [Terminology](Docs/Getting%20Started/Terminology.md) · [Declaring examples](Docs/Getting%20Started/InjectableExamples.md) · [Consuming examples](Docs/Getting%20Started/InjectedExamples.md) · [Migration from 1.x](Docs/Getting%20Started/Migration.md) |
| **[Macros and markers](Docs/TableOfContents.md#macros-and-markers)** | [`@Injectable`](Docs/Macros%20and%20Markers/Injectable.md) · [`@InjectableProviding`](Docs/Macros%20and%20Markers/InjectableProviding.md) · [`@InjectableValue`](Docs/Macros%20and%20Markers/InjectableValue.md) · [`@Singleton`](Docs/Macros%20and%20Markers/Singleton.md) · [`@Isolated`](Docs/Macros%20and%20Markers/Isolated.md) · [`@Injected`](Docs/Macros%20and%20Markers/Injected.md) · [Parameter markers](Docs/Macros%20and%20Markers/ParameterMarkers.md) · [Imported injectables](Docs/Macros%20and%20Markers/ImportedInjectables.md) · [Key aliases](Docs/Macros%20and%20Markers/ZerkAlias.md) |
| **[Features](Docs/TableOfContents.md#features)** | [Foreign types](Docs/Features/ForeignTypes.md) · [Generics](Docs/Features/Generics.md) · [Concurrency](Docs/Features/Concurrency.md) |
| **[The plugin](Docs/TableOfContents.md#the-plugin)** | [How it works](Docs/Plugin/HowItWorks.md) · [Generated code](Docs/Plugin/GeneratedCode.md) · [Settings](Docs/Plugin/Settings.md) · [Diagnostics](Docs/Plugin/Diagnostics.md) · [Limitations](Docs/Plugin/Limitations.md) |
| **[Testing](Docs/TableOfContents.md#testing)** | [Interjection](Docs/Testing/Interjection.md) · [Scopes](Docs/Testing/Scopes.md) · [Examples](Docs/Testing/Examples.md) |

## Installation

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
        dependencies: ["App", .product(name: "ZerkTesting", package: "Zerk")]
    ),
]
```

See [Installation](Docs/Getting%20Started/Installation.md) for Xcode projects, the three vended products, and targets in Swift 5 language mode.

## Quick start

```swift
import Zerk

// 1. A value the graph can use to satisfy parameters of matching type
@InjectableValue
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
    var apiService: ApiServicing   // resolved at init, at a compile-time-verified call site
}
```

The plugin generates (abridged — see [Quick start](Docs/Getting%20Started/QuickStart.md) for the whole file):

```swift
extension Zerk<ApiServicing> {
    nonisolated static var apiService: ApiServicing {
        // Where a test double stands in. Compiles to nothing in release.
        if let interjected = _$interjected(for: \.`apiService`) { return interjected }
        return _$zerk_singletons.apiService
    }

    nonisolated static func inject() -> ApiServicing { apiService }
}

// Also generated: one interjection point per member, named after its signature.
extension Zerk<ApiServicing>.Interjection {
    var `apiService`: Void {}
}
```

`@Injected var apiService` expands to a stored property whose default value is `Zerk<ApiServicing>.inject()`. The namespace itself is an empty `public enum Zerk<Injectable> {}`; everything lives in the generated extensions.

## Testing

Every generated member opens with a lookup against the interjections in force, so a test can stand a double in for one member or for a whole key — without a plugin on the test target, and without touching production code:

```swift
import Testing
import ZerkTesting
@testable import App

@Suite(.zerk)
struct FeedTests {
    @Test func usesTheDouble() {
        #Interject(\.apiService, with: MockApi())
        #expect(FeedViewModel().apiService is MockApi)
    }
}
```

Interjections belong to the scope in force — `.zerk` opens one per test, so suites keep running in parallel — and the lookup compiles to nothing outside `DEBUG`. See [Testing](Docs/Testing/Interjection.md).

## How it works

**Almost none of the code generation happens in the macros.** `@Injectable`, `@InjectableProviding`, `@Singleton` and `@Isolated` expand to *nothing*: they exist so the attribute is legal Swift for the plugin to read, and so the errors decidable from a single declaration are reported right at that declaration. `@Injected` is the one macro that generates code.

Everything else is the plugin, for one reason: an attached macro can only see the declaration it is attached to, while resolving a dependency graph requires the whole module. `ZerkPlugin` runs `ZerkCodegen` over every `.swift` file in the target — collect, resolve, generate — into a single `ZerkGenerated/ZerkInjections.swift`.

One consequence runs through the whole design: **the plugin reads syntax, never resolved types.** It cannot see through an unmarked `typealias`, cannot follow a conformance into another module, and cannot read your build settings. That is why type keys are canonicalized only as far as syntax allows, why `@Isolated<A>` exists, and why `ZerkSettings.json` exists.

See [How it works](Docs/Plugin/HowItWorks.md) and [Limitations](Docs/Plugin/Limitations.md).

## Requirements

- Swift 6.2 **toolchain** (`swift-tools-version: 6.1`); Zerk's own targets build in `.v6` language mode
- swift-syntax 602.x
- Platforms: iOS 13+, macOS 14+, watchOS 6+, tvOS 13+, visionOS 1+, Mac Catalyst 13+

6.2 is the floor because interjection points are named with raw identifiers (SE-0451). Your *language mode* is a separate question — a target with `SWIFT_VERSION = 5` under a Swift 6 toolchain is fully supported, with one construct needing an opt-in. See [Installation](Docs/Getting%20Started/Installation.md#consuming-targets-in-swift-5-language-mode).

## Migrating from Zerk 1.x

Zerk 2 is a ground-up replacement for the original runtime container: registration moved from `Zerk.store.singleton(...)` calls to source annotations, resolution moved from `Zerk.standardStorage.restore()` to generated members, and what used to fail at runtime now fails during the build. Migrate one module at a time — see [Migration](Docs/Getting%20Started/Migration.md).

## Contributing

The package builds with `swift build`. To run the tests:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

The `DEVELOPER_DIR` prefix is needed when `xcode-select` points at the Command Line Tools, whose swift-testing install is incomplete; a bare `swift test` then fails to launch with a missing `Testing` module or `lib_TestingInterop.dylib`.

Isolation and effects cannot be verified by comparing generated strings — text can look right and still not compile. `Tests/ZerkInjectionCodegenTests` therefore includes a compile harness that runs the codegen over a fixture and type-checks the result with a real `swiftc`, across both language modes and both `SWIFT_DEFAULT_ACTOR_ISOLATION` values. Add a case there for anything touching isolation, effects, or `sending`.

## License

See [LICENSE](LICENSE).
