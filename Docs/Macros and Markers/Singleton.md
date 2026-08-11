# `@Singleton`

`@Singleton` gives an injectable a single shared instance. This page covers what the marker
means, the storage Zerk generates for it, and the constraints that storage imposes.

For an instance that is shared but *not* forever — kept until a named scope is reset — see
[`@Scoped`](Scoped.md). It obeys every constraint on this page, for the same reasons.

## What it does

**`@Singleton`** — one shared instance per *type*, created lazily and thread-safely on first
access. A type injectable under several keys is built once and every key returns that same
instance. Reference types (class/actor) only. Singleton providers cannot be `async`/`throws`
and cannot require external arguments, and a singleton must resolve to one provider across
all of its keys — one instance cannot be built two ways.

```swift
@Singleton
@Injectable<ApiServicing>
final class ApiService: ApiServicing {
    @InjectableProviding
    init(baseURL: String) { … }
}
```

The macro itself is inert — it expands to nothing and reports nothing. It exists so the
attribute is legal Swift for the build plugin to read. Every `@Singleton` check lives in the
plugin, because whether a singleton can be built depends on the whole graph rather than on the
declaration alone.

## Storage

Shared instances live in a generated `private enum _$zerk_singletons`, one stored property per
singleton *type*, and each `Zerk<Key>` member is a getter reading from it. Given:

```swift
protocol Reading: AnyObject {}
protocol Writing: AnyObject {}

@Singleton
@Injectable<Reading, Writing>
final class Store: Reading, Writing {
    @InjectableProviding
    init() {}
}
```

Zerk generates (macro-shim preamble elided):

```swift
private enum _$zerk_singletons {
    nonisolated(unsafe) static let store: Store = Store()
}

extension Zerk<Reading> {
    nonisolated static var store: Reading {
        if let interjected = _$interjected(for: \.`store`) {
            return interjected
        }
        return _$zerk_singletons.store
    }

    nonisolated static func inject() -> Reading {
        store
    }

}

extension Zerk<Writing> {
    nonisolated static var store: Writing {
        if let interjected = _$interjected(for: \.`store`) {
            return interjected
        }
        return _$zerk_singletons.store
    }

    nonisolated static func inject() -> Writing {
        store
    }

}

extension Zerk<Reading>.Interjection {
    nonisolated var `store`: Void {}
}

extension Zerk<Writing>.Interjection {
    nonisolated var `store`: Void {}
}
```

Storage sits there rather than on `Zerk<Key>` because `Zerk<Reading>` and `Zerk<Writing>` are
distinct generic specializations with distinct static storage — a singleton held on them
directly would exist once *per key*, so `@Singleton` would only hold within a key. Two
consequences follow:

- The storage is typed as the provider's declared return type, falling back to the concrete
  type for an initializer. One instance serves every key, so a multi-key singleton's factory
  must return the concrete type; a single-key singleton's factory may return the key.
- A singleton must resolve to the same provider for every key it claims. Naming a different
  factory per key is a build error.

The storage property is named after the *type*, lower-camel-cased, independent of what the
generated members are called. It stays private regardless of `@Injectable(public: true)` —
only the getter is exported.

## Isolation

`@Singleton` storage mirrors provider isolation too: `nonisolated(unsafe) static let` for a
nonisolated provider, `@MainActor static let` for a `@MainActor` one (global-actor isolation
already protects the storage, so no `unsafe` escape hatch is needed).

```swift
@MainActor
@Singleton
@Injectable<Storing>
final class Cache: Storing {
    @InjectableProviding
    init(store: Store) {}
}
```

```swift
private enum _$zerk_singletons {
    @MainActor static let cache: Cache = Cache(store: Zerk<Store>.inject())
}
```

Singletons stay synchronous and non-throwing, so a singleton whose dependency lives in a
*different* domain is a build error — resolving it would need `await`, and a `static let`
initializer cannot. A nonisolated dependency reaching an isolated singleton is free; the error
fires only when two distinct domains collide:

```
error: @Singleton 'Cache' cannot be built: resolving 'Store' crosses an isolation boundary,
which requires 'await', but a singleton's storage is initialized synchronously. Make the
dependency share 'Cache's isolation, or drop @Singleton and resolve it through inject().
```

## Interjection

The interjection lookup lives in the getter rather than in the storage initializer, so a double
is consulted on every read — one installed after the first resolution still takes effect, and
interjecting a singleton never builds the real instance at all.

The guard cannot live in the storage: it is per key, and there is one storage for both keys.
Each getter carries its own, and each key gets its own interjection point, even though one
instance backs them all.

## The `Sendable` check

When a singleton is injected across an isolation boundary, Zerk emits a `Sendable` constraint
check next to an explanatory comment. Zerk does not attempt to prove `Sendable` from syntax;
the check costs nothing when the type already conforms, and it puts the compiler's complaint on
a line that explains itself.

```swift
private func _$zerk_sendable_conformance_check<T: Sendable>(_: T.Type) {}

private func _$zerk_sendable_conformance_check_Logger_in_Reporter() {
    // '@Singleton Logger' is injected into 'Reporter'.
    // Singletons that cross isolation domains must be Sendable.
    _$zerk_sendable_conformance_check(Logger.self)
}
```

This is the one diagnostic that comes from the compiler rather than from Zerk.

## Constraints

**`@Singleton` constraints.** Reference types only; provider must be synchronous and
non-throwing; no external arguments; and no dependency in a different isolation domain,
since resolving one would need `await`.

The reference-type rule is checked where it can be seen. On a type declaration Zerk reads
`struct` or `enum` and refuses. On an [`@Injectable` declaration](../Features/ForeignTypes.md)
the produced type is only a *name* — Zerk reads syntax and never resolves it — so the check
cannot be made and the developer's word is taken, as `@Isolated`'s is. Marking a value type
that way shares a copy per read rather than an instance: inert rather than unsound.

**Exactly one provider — in total, not per key.** This is the constraint most worth stating
plainly, because the weaker reading is self-contradictory. One instance is built once and
stored once; every key is a way of *reading* that storage, not a way of building it. So a
singleton injectable under three keys still has one provider, and all three keys resolve
through it.

Zerk enforces that as two checks, because the two ways of breaking it are different
mistakes with different fixes:

- **Two providers for one key.** Both members would read the same storage, so asking for
  one factory would hand back whatever the other built.
- **A different provider per key.** Each key names one provider, but not the *same* one —
  and one instance cannot be built two ways.

A singleton injectable under several keys must also be built by an initializer or by a
factory returning the concrete type: its one instance is stored once and read through every
key, so storage typed as one of the keys cannot serve the others.

The corresponding errors, in Zerk's own words:

| what you wrote | error |
|---|---|
| `@Singleton` on a struct or enum | `@Singleton can only be applied to reference types (class or actor).` |
| `@Singleton` on a generic `@Injectable` declaration | `@Singleton cannot be applied to the generic type 'Box'. …` |
| a provider with a parameter the graph cannot satisfy | `@Singleton injectables cannot accept external arguments.` |
| an `async` or `throws` provider | `@Singleton providers cannot be async or throwing.` |
| two providers for one key | `@Singleton 'Loader' declares multiple providers for 'Loading'. A singleton is stored once and read through every key it claims, so it has exactly one provider in total — not one per key. Keep whichever builds the shared instance.` |
| a different factory per key | `@Singleton 'Dep' resolves to different providers for … A singleton has one instance, so it must have one provider across all its keys.` |
| a multi-key factory returning a key | `@Singleton 'Dep' is injectable under 2 keys, so its provider must return 'Dep' rather than 'TypeA'. One instance is shared by every key, and storage typed 'TypeA' cannot serve the others.` |

## Not on generic types

**No `@Singleton`.** Its storage is a static stored property, which Swift does not allow in a
generic type — there is nowhere to keep one instance per specialization. This one is permanent.

```
error: @Singleton cannot be applied to the generic type 'Registry'. A singleton is stored in a
static stored property, which Swift does not allow in a generic type — there is nowhere to keep
one instance per specialization.
```

---

[← Table of contents](../TableOfContents.md)

**See also:** [`@Injectable`](Injectable.md) · [`@InjectableProviding`](InjectableProviding.md) · [`@Isolated`](Isolated.md) · [Concurrency](../Features/Concurrency.md) · [Generics](../Features/Generics.md) · [Generated code](../Plugin/GeneratedCode.md) · [Diagnostics](../Plugin/Diagnostics.md) · [Interjection](../Testing/Interjection.md)
