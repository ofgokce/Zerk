# Testing — worked examples

Every example here is adapted from Zerk's own test suite under `Tests/ZerkTests/`, which
exercises each of these shapes against the real macros and the real plugin. The API
spellings are verified against `Sources/ZerkTesting/` and `Sources/Zerk/Interjection/`.

For what an interjection point *is* and how it is named, read
[Interjection](Interjection.md) first. For how a scope is established, read
[Scopes](Scopes.md).

## The graph these examples stand doubles in for

```swift
protocol Loading { var source: String { get } }

@Injectable<Loading>(primary: true)
struct LiveLoader: Loading {
    let source = "live"

    @InjectableProviding<Loading>(primary: true)
    static func live() -> Loading { LiveLoader() }

    @InjectableProviding<Loading>
    static func cached() -> Loading { LiveLoader() }
}
```

Which generates two named members and two interjection points:

```swift
extension Zerk<Loading>.Interjection {
    nonisolated var `cached`: Void {}
    nonisolated var `live`: Void {}
}
```

## 1. The minimal case

```swift
import Testing
import ZerkTesting
@testable import App

struct MockLoader: Loading { let source = "mock" }

@Suite(.zerk)
struct FeedTests {
    @Test func usesTheDouble() {
        #Interject(\.live, with: MockLoader())
        #expect(Zerk<Loading>.live.source == "mock")
    }
}
```

Three things are doing work. `@testable import App` reaches the interjection points, which
are `internal` to the module that declares the injectables — **the test target needs no
plugin**. `.zerk` puts a scope in force. `#Interject` registers into that scope.

## 2. A whole key at once, and overriding it

A blanket names its key and covers every member of it:

```swift
@Test func blanketCoversEveryMember() {
    #Interject<Loading>(with: MockLoader())
    #expect(Zerk<Loading>.live.source == "mock")
    #expect(Zerk<Loading>.cached.source == "mock")
    #expect(Zerk<Loading>.inject().source == "mock")
}
```

A member-specific interjection beats a blanket over the same key, so a blanket can set the
baseline and one member stay pinned:

```swift
@Test func memberBeatsBlanket() {
    #Interject<Loading>(with: MockLoader())
    #Interject(\.cached, with: PinnedLoader())
    #expect(Zerk<Loading>.live.source == "mock")     // from the blanket
    #expect(Zerk<Loading>.cached.source == "pinned") // more specific wins
}
```

## 3. A parameterized member — the real factory never runs

```swift
@Injectable
struct SeededToken {
    let value: Int
    @InjectableProviding
    init(seed: Int) { self.value = seed }
}
```

```swift
@Test func parameterized() {
    #Interject(\.seededToken, with: SeededToken(seed: 999))
    #expect(Zerk<SeededToken>.seededToken(seed: 1).value == 999)
}
```

The argument is accepted and ignored: the lookup sits at the top of the member, so the
double is returned before `SeededToken(seed:)` is ever called. A blanket says the same
thing more strongly — "this key resolves to this, however it was asked for".

## 4. Two tests interjecting the same key, in parallel

This is the property the scoping design exists for, so it is worth asserting directly.
Adapted from `ZerkInterjectionsTests`:

```swift
@Suite("Interjection isolation", .zerk)
struct IsolationTests {

    @Test func parallelA() async throws {
        #Interject<Loading>(with: TaggedMock(tag: "A"))
        for _ in 0..<40 {
            #expect((Zerk<Loading>.live as? TaggedMock)?.tag == "A")
            try await Task.sleep(nanoseconds: 100_000)
        }
    }

    @Test func parallelB() async throws {
        #Interject<Loading>(with: TaggedMock(tag: "B"))
        for _ in 0..<40 {
            #expect((Zerk<Loading>.live as? TaggedMock)?.tag == "B")
            try await Task.sleep(nanoseconds: 100_000)
        }
    }

    @Test func untouchedResolvesReal() async throws {
        for _ in 0..<40 {
            #expect(Zerk<Loading>.live is TaggedMock == false)
            try await Task.sleep(nanoseconds: 100_000)
        }
    }
}
```

The sleeps interleave the three tests deliberately. Each sees only its own doubles, and the
third sees the real graph throughout — because `ZerkInterjections.isRecursive` is `true`, so
a suite-level trait opens a scope around **each test** rather than once around the suite.

No `.serialized`, no shared reset, no teardown.

## 5. A shared, named set reused by two suites

`ZerkInterjections` is an ordinary value as well as a trait, so a set worth reusing can be
named:

```swift
let apiDoubles = ZerkInterjections {
    #Interject<ApiServicing>(with: MockApi())
    #Interject(\.staging, with: Session.mock)
}

@Suite(apiDoubles) struct CheckoutTests { … }
@Suite(apiDoubles) struct FeedTests { … }
```

Still per test, not per suite: the closure runs for each, so the doubles are rebuilt and
sharing one set between suites carries no state across. A test's own interjections win over
the shared ones.

The inline equivalent, for a single suite:

```swift
@Suite(.zerk { #Interject<Loading>(with: MockLoader()) })
struct SharedTests { … }
```

## 6. The multi-statement form

`with:` takes a single expression. When building the double needs more than one statement,
use the closure form:

```swift
#Interject<ApiServicing> {
    let api = MockApi()
    api.host = "staging"
    return api
}
```

Both forms exist for the key-path variant too — `#Interject(\.live) { … }`.

## 7. When the double is built, and what has to be `Sendable`

`with:` is an `@autoclosure`, so it runs on **every resolution** rather than once at
registration — a fresh double each time, matching Zerk's transient default. Built inline,
nothing is captured and nothing needs to be `Sendable`:

```swift
#Interject(\.live, with: MockLoader())      // a new MockLoader per resolution
```

To hold one and assert on it afterwards, capture it — which requires the double to be
`Sendable`, since a scope is shared across tasks:

```swift
let mock = RecordingLoader()                // must be Sendable
#Interject(\.live, with: mock)
_ = Zerk<Loading>.inject()
#expect(mock.callCount == 1)
```

## 8. A generic key

A generic key is interjected per specialization, through the marker protocol the plugin
generates. Adapted from `GenericKeyInterjectionTests`:

```swift
@Test func perSpecialization() {
    let double = Repository<String>(…)
    #Interject(\.`repository`, with: double)

    // Reaches exactly the specialization registered…
    let strings: Repository<String> = Zerk<Repository<String>>.inject()
    #expect(strings.stamp.serial == double.stamp.serial)

    // …and only that one. A sibling is built for real.
    let ints: Repository<Int> = Zerk<Repository<Int>>.inject()
    #expect(ints.stamp.serial != double.stamp.serial)
}
```

The blanket form names the specialization in the key:

```swift
#Interject<Repository<String>>(with: double)
```

There is no way to cover *every* specialization at once — a closure cannot be generic, so
the registration has to name the specialization it covers. See
[Generics](../Features/Generics.md).

A **parameterized existential** key is reachable by key only, since an existential conforms
to nothing and so can carry no marker and no point:

```swift
#Interject<any Pairing<Int, String>>(with: Pair(99, "z"))
```

## 9. Interjection does not short-circuit resolution

A member's dependencies are defaulted arguments, and Swift evaluates them before the body
runs — so an interjected value still builds its real dependency subtree first:

```swift
let before = CodecCounter.builds.count
_ = Zerk<Repository<String>>.inject() as Repository<String>
#expect(CodecCounter.builds.count > before)   // the real Codec was built anyway
```

Worth knowing when a dependency's construction has side effects or is expensive. Interject
the dependency too if that matters.

A `@Singleton` or `@Scoped` member is the exception. Its subtree is built inside the storage
initializer or inside the closure handed to its box, and the guard returns before either — so
interjecting one builds nothing:

```swift
let before = ScopedDependency.buildCount
#Interject<Repositorying>(with: FakeRepository())
#expect(Zerk<Repositorying>.inject() is FakeRepository)
#expect(ScopedDependency.buildCount == before)   // the real subtree never ran
```

## 10. A scoped instance, and what the double does to its box

A [`@Scoped`](../Macros%20and%20Markers/Scoped.md) key is interjected exactly like any other
— there is nothing scope-specific to write — and the box is left untouched:

```swift
@Suite("Session", .zerk)
struct SessionTests {
    @Test func usesTheDouble() {
        #Interject<Caching>(with: MockCache())
        #expect(Zerk<Caching>.inject() is MockCache)
    }
}
```

Two properties make that safe, and both follow from the guard sitting ahead of the box rather
than from anything the test does:

- **the real instance is never built**, so a scoped type with an expensive constructor costs
  nothing in a test that stands something in for it;
- **the double is never cached**, so it cannot outlive the scope that registered it. Were it
  stored in the box, it would leak into every test that ran afterwards — the exact failure
  per-test interjection scopes exist to prevent.

`Zerk.reset(_:)` is a *runtime* API, not a testing one, and it reaches every box in the
process. Prefer interjection in tests; reach for a reset only when the thing under test is
the reset behaviour itself, and serialize those tests, since a scope is process-wide by
design.

## 11. XCTest

Swift Testing traits do not apply, so open the scope by overriding `invokeTest()`. The
synchronous `withInterjections` overload exists for exactly this:

```swift
import XCTest
@testable import App

final class FeedTests: XCTestCase {
    override func invokeTest() {
        Zerk.withInterjections {
            super.invokeTest()
        }
    }

    func testUsesTheDouble() {
        #Interject(\.live, with: MockLoader())
        XCTAssertEqual(Zerk<Loading>.live.source, "mock")
    }
}
```

`Zerk.withInterjections` is spelled on `Zerk<Never>` so it reads without naming a key — a
scope covers every key at once.

## 12. SwiftUI previews

A preview is the one place `#Interject` works outside a test scope, because the process
genuinely is the scope:

```swift
#Preview {
    ContentView().interjecting {
        #Interject<ApiServicing>(with: MockApi())
    }
}
```

The `interjecting` modifier exists because a `#Preview` body is a `@ViewBuilder`, which
rejects `#Interject` as `type '()' cannot conform to 'View'`; the modifier's closure is a
plain `() -> Void`.

A preview's interjections outlive the view that made them and accumulate across previews in
one process — so register everything a preview needs rather than relying on a neighbour's.

Outside a scope and outside a preview, `#Interject` **traps** rather than leaking into
whatever runs alongside.

## 13. What none of this costs in release

The lookup at the top of every member is `@inlinable` and returns `nil` outside `DEBUG`, so
an optimized build reduces each member to its construction alone — no branch, no key-path
formation. Nothing above needs to be compiled out by hand.

---

[← Table of contents](../TableOfContents.md)

**See also:** [Interjection](Interjection.md) · [Scopes](Scopes.md) · [Generics](../Features/Generics.md) · [Consuming — examples](../Getting%20Started/InjectedExamples.md)
