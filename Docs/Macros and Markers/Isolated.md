# `@Isolated`

`@Isolated<A>` tells Zerk which global actor a declaration is isolated to, when the build plugin
cannot see it. This page covers the two cases that need it, where it may be attached, and what
Zerk does and does not check.

## What it does

**`@Isolated<A>`** — tells Zerk which global actor a declaration is isolated to, when the build
plugin cannot see it. It is **corrective, not declarative**: it restates what the compiler
already believes so the generated members mirror the right isolation. Claiming something untrue
produces generated code that will not compile.

## When you need it

Global actor detection is heuristic. `@MainActor` is recognized exactly; any other attribute
ending in `Actor` is assumed to be a global actor. Two cases fall outside that — a custom global
actor whose name does not end in `Actor` (Zerk's attribute heuristic misses it), and isolation
inherited through a conformance (invisible to a syntax-only plugin):

```swift
@Isolated<DataStore>
@DataStore
@Injectable<Storing>
final class FileStore: Storing { init() {} }
```

```swift
extension Zerk<Storing> {
    @DataStore static var fileStore: Storing {
        if let interjected = _$interjected(for: \.`fileStore`) {
            return interjected
        }
        return FileStore()
    }

    @DataStore static func inject() -> Storing {
        fileStore
    }

}
```

For "this is nonisolated", use Swift's own `nonisolated` keyword — it is real, and Zerk reads it.

## Where it may be attached

`@Isolated` may be attached to a type, an initializer, an `@InjectableProviding` factory, or an
`@InjectableValue`; the innermost annotation wins, exactly as Swift's own isolation inference
works. A factory carrying `@Isolated<MainActor>` inside a type marked `@Isolated<DataStore>`
generates a `@MainActor` member.

An `actor` is the exception: its construction is nonisolated, so isolating it to a global actor
is an error. Actor isolation applies to the actor's methods, not to building it.

## What Zerk checks

`@Isolated<A>` is unverified. It states what the compiler already believes; Zerk cannot check
that claim and will generate code matching whatever you wrote. The two things it does check are
local contradictions, where one of the two annotations must be wrong and guessing which would
generate code that does not compile:

- `@Isolated<A>` on a declaration that is also `nonisolated`.
- `@Isolated<A>` on a declaration carrying a *recognized* global-actor attribute that is not
  `A` — `@Isolated<MainActor>` next to `@SomeActor`.

The second check only fires for attributes the heuristic recognizes, which is exactly why the
`@Isolated<DataStore>` + `@DataStore` pairing above is accepted rather than flagged.

---

[← Table of contents](../TableOfContents.md)

**See also:** [`@Injectable`](Injectable.md) · [`@InjectableProviding`](InjectableProviding.md) · [`@InjectableValue`](InjectableValue.md) · [`@Singleton`](Singleton.md) · [Concurrency](../Features/Concurrency.md) · [Settings](../Plugin/Settings.md) · [Limitations](../Plugin/Limitations.md) · [Diagnostics](../Plugin/Diagnostics.md)
