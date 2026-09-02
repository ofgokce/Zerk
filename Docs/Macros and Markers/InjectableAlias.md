# Key aliases

Zerk matches dependencies by the spelling of a type, so two names for one type are two keys until
you say otherwise. This page covers both ways of saying it — `@InjectableAlias` on a typealias you
declare, `#InjectableAlias<A, B>()` for types you cannot annotate — and what merging changes in the
generated file.

## What they do

**`@InjectableAlias` / `#InjectableAlias<A, B, …>()`** — tells Zerk that two names are one key. Zerk matches
by spelling, so without this a provider registered as `Storing` will not satisfy a parameter
written `Persisting`:

```swift
@InjectableAlias
typealias Persisting = Storing        // the typealias is in this target

#InjectableAlias<Storing, Caching>()        // it is not — list the types instead
```

An unmarked typealias merges nothing. Given a provider registered as `Storing` and a consumer
whose parameter is written `Persisting`, the plugin has no reason to believe the two are related,
so the dependency bubbles to the caller:

```swift
protocol Storing {}
typealias Persisting = Storing

@Injectable<Storing>
final class FileStore: Storing {
    @InjectableProviding
    init() {}
}

@Injectable
final class Consumer {
    @InjectableProviding
    init(store: Persisting) {}
}
```

```swift
    nonisolated static func inject(store: Persisting) -> Consumer {
```

Marking the typealias resolves it instead — the parameter keeps its own spelling, and the default
that fills it goes through the merged key:

```swift
@InjectableAlias
typealias Persisting = Storing
```

```swift
extension Zerk<Consumer> {
    nonisolated static func consumer(store: Persisting = Zerk<Persisting>.inject()) -> Consumer {
        …
    }

    nonisolated static func inject() -> Consumer {
        consumer()
    }

}
```

## Why merging is required

Merging is not just convenience. `Zerk<Storing>` and `Zerk<Persisting>` are the *same* generic
specialization, so registering an injectable under each would emit two `inject()` members on one
type — `invalid redeclaration of 'inject()'`.

With the alias understood, both registrations land in one extension and the primary decides
`inject()`:

```swift
@InjectableAlias
typealias Persisting = Storing

@Injectable<Storing>(primary: true)
final class FileStore: Storing {
    @InjectableProviding
    init() {}
}

@Injectable<Persisting>
final class MemoryStore: Storing {
    @InjectableProviding
    init() {}
}
```

```swift
extension Zerk<Storing> {
    nonisolated static var fileStore: Storing {
        if let interjected = _$interjected(for: \.`fileStore`) {
            return interjected
        }
        return FileStore()
    }

    nonisolated static var memoryStore: Storing {
        if let interjected = _$interjected(for: \.`memoryStore`) {
            return interjected
        }
        return MemoryStore()
    }

    nonisolated static func inject() -> Storing {
        fileStore
    }

}
```

Two types under one key still need a primary, and the error says so in terms of the alias rather
than leaving you to find it:

```
error: Multiple types are injectable under 'Storing' (FileStore, MemoryStore) and none is
primary. 'Storing' and 'Persisting' are the same type (registered via @InjectableAlias), so those
declarations claim one key. Mark one with @Injectable(primary: true).
```

## Transitivity and the representative

Equivalence is transitive, and the group is represented by the underlying type where there is one
(`@InjectableAlias typealias Names = [String]` emits `Zerk<Array<String>>`), otherwise by the
alphabetically first name.

`A = B` and `B = C` therefore make one group of three, however the two forms are mixed. Election
prefers a spelling that is nobody's alias — a typealias's left-hand side is by construction a name
for something else — and is alphabetical among the remaining candidates, so a group merging a
`#InjectableAlias` list of peers with a marked typealias can elect a peer rather than the typealias's
right-hand side.

The representative decides which extension is emitted, not how a key may be written. An
existential spelling survives the merge — `@Injectable<any Persisting>` emits
`extension Zerk<any Storing>` — because every member of the group denotes the same type.

## `#InjectableAlias<A, B, …>()`

The freestanding form expands to a private, never-called function that pairs the listed types
through a generic same-type parameter, so **the compiler** checks the claim — listing types that
are not interchangeable is a build error at the `#InjectableAlias` line. The check is invariant, so a
subclass and its superclass are correctly rejected. The trailing `()` is required: written bare,
Swift does not hand the generic arguments to the macro.

The expansion, with a compiler-unique function name and one call per unordered pair:

```swift
private func zerk_alias_check() {
    func interchangeable<T>(_: T.Type, _: T.Type) {}
    interchangeable(Storing.self, Caching.self)
}
```

The plugin takes the listing on trust when it builds the key graph, which is why the generated
code has to be what checks it: a wrong `#InjectableAlias` would otherwise silently merge two unrelated
keys and misroute every dependency of both. Every listed type must also be a distinct key —
listing one twice, or listing `[String]` and `Array<String>`, is a no-op you probably did not
intend and is refused.

## Generic typealiases are rejected

Generic typealiases are rejected — substituting their parameters would need real type resolution.
Alias a concrete instantiation instead.

```
error: @InjectableAlias does not support generic typealiases. 'Pair' has type parameters, and Zerk
matches keys by spelling rather than resolving them. Alias a concrete instantiation instead,
e.g. typealias IntPair = Pair<Int>.
```

The plugin does not collect the declaration either, so a rejected alias merges nothing rather
than merging something meaningless.

## Diagnostics

| what you wrote | error |
|---|---|
| `@InjectableAlias` on something other than a typealias | `@InjectableAlias can only be applied to a typealias.` |
| `@InjectableAlias` on a generic typealias | `@InjectableAlias does not support generic typealiases. 'Pair' has type parameters, and Zerk matches keys by spelling rather than resolving them. Alias a concrete instantiation instead, e.g. typealias IntPair = Pair<Int>.` |
| `#InjectableAlias<A>()`, or `#InjectableAlias<A, B>` without the trailing `()` | `#InjectableAlias needs at least two types to relate, written as #InjectableAlias<A, B>() — the trailing '()' is required, without it Swift does not pass the types to the macro.` |
| the same type listed twice | `#InjectableAlias lists 'Storing' twice. Every listed type must be a distinct key.` |
| two spellings that are already one key | `#InjectableAlias lists '[String]' and 'Array<String>', which are already one key. Every listed type must be a distinct key.` |
| two types under one aliased key, none primary | `Multiple types are injectable under 'Storing' (FileStore, MemoryStore) and none is primary. 'Storing' and 'Persisting' are the same type (registered via @InjectableAlias), so those declarations claim one key. Mark one with @Injectable(primary: true).` |
| types that are not interchangeable | the compiler's own, at the `#InjectableAlias` line |

---

[← Table of contents](../TableOfContents.md)

**See also:** [`@Injectable`](Injectable.md) · [`@InjectableValue`](InjectableValue.md) · [Imported injectables](ImportedInjectables.md) · [Generics](../Features/Generics.md) · [How it works](../Plugin/HowItWorks.md) · [Generated code](../Plugin/GeneratedCode.md) · [Diagnostics](../Plugin/Diagnostics.md) · [Terminology](../Getting%20Started/Terminology.md)
