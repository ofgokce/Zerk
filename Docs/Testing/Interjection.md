# Interjection

The plugin gives every generated member a named interjection point, so `#Interject` can
stand a double in for any injectable — one member, or a whole key at once — without touching
production code. This page covers what a point is, how it is named, the `#Interject` forms
that reach it, and what all of it costs in release.

## Every member opens with a lookup

Every generated member opens with a lookup against the interjections in force, and the
plugin declares a matching point on that key's `Interjection` namespace — named, via a raw
identifier, verbatim after the member's signature. A generic key works the same way, through
a generated marker protocol — see [Generic keys](#generic-keys):

```swift
// Generated:
extension Zerk<UserService> {
    nonisolated static func live(apiService: ApiServicing = Zerk<ApiServicing>.inject()) -> UserService {
        if let interjected = _$interjected(for: \.`live`) {
            return interjected
        }
        return LiveUserService.live(apiService: apiService)
    }
    …
}

extension Zerk<UserService>.Interjection {
    var `live`: Void {}
}
extension Zerk<SeededToken>.Interjection {
    var `seeded`: Void {}
}
```

The points are kept off `Zerk<Key>` itself. Hung there, the point for an argument-free
member would collide with the member — both would be `static var live` — and only
parameterized members would have a free name. In the namespace every member gets one,
whatever its shape, and `Zerk<Key>`'s own surface is left alone.

## Reaching the points from a test

These are `internal` to the declaring module, so the test target reaches them with
`@testable import App` — no plugin on the test target. Add the `ZerkTesting` library for the
`.zerk` trait, which gives each test a scope of its own:

```swift
import Testing
import ZerkTesting
@testable import App

struct MockUserService: UserService {
    func requestPath() -> String { "mock/users" }
    var loggerSerial: Int { -1 }
}

@Suite(.zerk)
struct FeedTests {

    @Test func usesTheDouble() {
        #Interject(\.live, with: MockUserService())
        #expect(FeedViewModel().userService is MockUserService)
    }

    // A parameterized provider is named the same way, and the real factory never runs.
    @Test func parameterized() {
        #Interject(\.seeded, with: SeededToken(value: 999))
        #expect(Zerk<SeededToken>.seeded(seed: 1).value == 999)
    }
}
```

Outside a scope `#Interject` traps rather than leaking into whatever runs alongside — see
[Scopes](Scopes.md) for the trait, for reusable sets, for XCTest, and for the one place the
process itself is the scope.

## The `#Interject` forms

Four, two axes: whether the double covers one member or the whole key, and whether it takes
one expression or several statements to build.

| form | covers |
|---|---|
| `#Interject<Key>(with: MockApi())` | every member of the key |
| `#Interject<Key> { … }` | every member, when the double needs more than one statement |
| `#Interject(\.live, with: MockApi())` | one member |
| `#Interject(\.live) { … }` | one member, multi-statement |

## How a point is named

**A point is named as short as the key allows.** A member name used once takes the bare
name; overloads take Swift's own selector form; and only overloads differing *solely* by
parameter type spell them out:

| members sharing the name | point |
|---|---|
| one | `\.live` |
| several, distinct labels | `` \.`loader(store:)` `` |
| several, same labels | `` \.`loader(store: Disk)` `` |

A group escalates as a whole, so every overload of one name is spelled the same way. Adding
an overload can therefore rename a point and turn interjections naming it into compile
errors — which is the intended outcome, since the name really did stop identifying one
member.

## Naming a member

The key is inferred from the key path, and from `with:` when one member name belongs to more
than one key. Only a genuine tie needs it spelled — `#Interject<UserService>(\.live, with: …)`
— and Swift says so when it happens. Because the point is a real declaration, a renamed
provider makes the interjection a *compile error* rather than something that silently stops
applying.

## A whole key at once

A blanket interjection names its key and covers every member of it, parameterized ones
included — arguments are ignored, because a blanket says "this key resolves to this, however
it was asked for". A member-specific interjection beats a blanket over the same key, so a
blanket can set the baseline and one member stay pinned:

```swift
#Interject<ApiServicing>(with: MockApi())
#Interject<ApiServicing> { MockApi(host: "staging") }   // multi-statement form
```

## When the double is built

`with:` is an autoclosure, so it runs on every resolution rather than once at registration —
a fresh double each time, matching Zerk's transient default. To hold one and assert on it
afterwards, capture it (`#Interject(\.live, with: mock)`), which requires `mock` to be
`Sendable` since a scope is shared across tasks. Built inline, nothing is captured and
nothing needs to be `Sendable`.

## Generic keys

**Generic keys are interjectable per specialization.** The namespace extension cannot name
the parameter, so the plugin declares a marker protocol the base type conforms to, and scopes
the point by that:

```swift
protocol `_$ZerkInjectable_Cache` {}
extension Cache: `_$ZerkInjectable_Cache` {}
extension Zerk.Interjection where Injectable: `_$ZerkInjectable_Cache` {
    var `cache`: Void {}
}
```

So both forms work, and each reaches exactly the specialization it names — `Cache<Int>` is
untouched by a double registered for `Cache<String>`:

```swift
#Interject(\.cache, with: Cache<String>(…))
#Interject<Cache<String>>(with: …)
```

There is no way to stand one double in for *every* specialization at once: a closure cannot
be generic, so the registration has to name the specialization it covers.

A **parameterized existential** key is the exception. An existential conforms to nothing, so
it can have no marker and no point — it is reachable by key only, with
`#Interject<any Boxable<Int, String>>(with:)`.

[Generics](../Features/Generics.md) has the depth: the three ways to register a generic type,
and what each can do.

## In release, none of this exists

The lookup is `@inlinable` and compiles to `nil` outside `DEBUG`, so an optimized build
reduces each member to its construction alone — no branch, no key-path formation.

---

[← Table of contents](../TableOfContents.md)

**See also:** [Scopes](Scopes.md) · [Testing examples](Examples.md) · [Generics](../Features/Generics.md) · [Generated code](../Plugin/GeneratedCode.md) · [Terminology](../Getting%20Started/Terminology.md)
