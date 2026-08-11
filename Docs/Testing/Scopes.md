# Interjection scopes

Interjections belong to the scope in force. This page covers what a scope is, how one is opened — the `.zerk` trait, a named set of interjections, `Zerk.withInterjections` under XCTest — and what happens outside one.

"Scope" means two unrelated things in Zerk, and this is the testing one: a task-local boundary that keeps one test's doubles out of another's. The other is an [injection scope](../Macros%20and%20Markers/Scoped.md) — a named lifetime that `@Scoped` instances are kept for and `Zerk.reset(_:)` clears. They share a word and nothing else.

## What a scope is

A scope is a task-local binding. `ZerkInterjector.current` is a `@TaskLocal` holding a `ZerkInterjector`, and `Zerk.withInterjections { }` binds a fresh one for the duration of the operation it is given:

```swift
try await Zerk.withInterjections {
    #Interject<ApiServicing>(with: MockApi())
    …
}
```

It is spelled on `Zerk<Never>` so it reads as `Zerk.withInterjections { … }` without naming a key, since a scope covers every key at once. There are two overloads — an `async rethrows` one and a synchronous `rethrows` one — so a test body that never suspends, and XCTest's `invokeTest()`, need no `await`.

`ZerkInterjector` is deliberately a **class**. The task local holds a reference, so `#Interject` can add to the set in the middle of a test without wrapping everything after it in a closure. Isolation comes from each test being handed its own set, not from rebinding a value.

## The `.zerk` trait

`.zerk` comes from the `ZerkTesting` library — a test target adds it alongside `@testable import` of the module under test (see [Installation](../Getting%20Started/Installation.md)).

`.zerk` opens one scope per test — `isRecursive`, so a suite-level trait scopes each test rather than the suite — which is what lets tests interject the same key in parallel without seeing each other.

```swift
@Suite(.zerk)
struct FeedTests {

    @Test func usesTheDouble() {
        #Interject(\.live, with: MockUserService())
        #expect(FeedViewModel().userService is MockUserService)
    }
}
```

Recursion is the load-bearing part: applying the trait to a suite gives each test inside its own scope rather than wrapping the suite in one, which is what makes those tests independent of each other rather than merely separated from everything outside. Parameterized and repeated tests take a scope per case for the same reason.

## Starting a suite from a shared set

Start a suite from a shared set with `.zerk { #Interject<ApiServicing>(with: MockApi()) }`; it runs per test, and a test's own interjections win — its registrations land in the same scope afterwards.

```swift
@Suite(.zerk { #Interject<ApiServicing>(with: MockApi()) })
struct CheckoutTests {

    @Test func usesTheSharedDouble() { … }

    @Test func overridesIt() {
        #Interject<ApiServicing>(with: FailingApi())
        …
    }
}
```

## Naming a set

A set worth reusing can be named, since `ZerkInterjections` is an ordinary value as well as a trait:

```swift
let apiDoubles = ZerkInterjections {
    #Interject<ApiServicing>(with: MockApi())
    #Interject(\.staging, with: Session.mock)
}

@Suite(apiDoubles) struct CheckoutTests { … }
@Suite(apiDoubles) struct FeedTests { … }
```

It is still per test, not per suite: the doubles are rebuilt for each, so sharing one between suites carries no state across.

## Under XCTest

Override `invokeTest()` to wrap `super.invokeTest()` in `Zerk.withInterjections { }`:

```swift
final class FeedTests: XCTestCase {

    override func invokeTest() {
        Zerk.withInterjections {
            super.invokeTest()
        }
    }
}
```

The synchronous overload is the one that applies here, so nothing about the test method's signature changes.

## Outside a scope

Outside a scope, `#Interject` **traps** rather than leaking into whatever runs alongside. With no binding in force, `ZerkInterjector.current` is `processDefault` — one shared object — so an interjection made there would surface in every other test running concurrently, including tests that never mention interjection, which would then fail somewhere unrelated. Refusing at the point of the mistake is cheaper than that, and the message names the fix:

> Zerk: interjected outside a scope, which would leak into every test running alongside this one. Use the `.zerk` trait on the suite, or wrap the work in `Zerk.withInterjections { }`. Unscoped interjection is allowed only in SwiftUI previews, where the process is the scope.

## The SwiftUI preview exception

The one exception is a SwiftUI preview, where the process genuinely is the scope:

```swift
#Preview {
    Zerk.view {
        ContentView()
    } withInterjections: {
        #Interject<ApiServicing>(with: MockApi())
    }
}
```

`Zerk.view` earns its place twice over. Its interjections closure is a plain `() -> Void`, so `#Interject` can be written inside it — a `#Preview` body is a `@ViewBuilder`, which rejects a `Void` expression as `type '()' cannot conform to 'View'`. And it takes the content as a *closure*, which it calls after registering, so the doubles are in force while the view is built. That matters because `@Injected` resolves during `init`: build the view first and its own injected properties hold the real graph while only its children see the doubles. See [Examples](Examples.md#12-swiftui-previews).

A preview's interjections outlive the view that made them and accumulate across previews in one process, so register everything a preview needs rather than relying on a neighbour's.

A task-local scope could not serve a preview at all: SwiftUI constructs child views and re-invokes `body` long after the `#Preview` closure has returned, by which point any binding has unwound. Registration goes to the process-wide set instead. `ZerkInterjector.current.removeAll()` drops every interjection, for a preview that wants a clean slate; a test should take a fresh scope rather than clear one.

## In release

**In release, none of this exists.** The lookup is `@inlinable` and compiles to `nil` outside `DEBUG`, so an optimized build reduces each member to its construction alone — no branch, no key-path formation.

---

[← Table of contents](../TableOfContents.md)

**See also:** [Interjection](Interjection.md) · [Testing examples](Examples.md) · [Concurrency](../Features/Concurrency.md) · [Installation](../Getting%20Started/Installation.md)
