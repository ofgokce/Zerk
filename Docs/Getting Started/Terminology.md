# Terminology

The vocabulary the rest of these pages assume. Every term here names something the plugin
actually does — a record it keeps, a member it emits, or a decision it makes — so the
definitions are written against the generated code rather than around it.

## The graph

### Key

The type a dependency is asked for. `Zerk<Key>` is where everything about it lives, and a
provider parameter written `apiService: ApiServicing` is a request for the key
`ApiServicing`. Keys are matched by **spelling**, canonicalized only as far as syntax
allows — `[T]`/`Array<T>`, `[K: V]`/`Dictionary<K, V>`, `T?`/`T!`/`Optional<T>`,
`()`/`Void`, `(T)`/`T`, `A & B`/`B & A`, and `P`/`any P` are one key each, and
canonicalization nests, so `[String]?` and `Optional<Array<String>>` agree. What needs
real type resolution stays distinct: module qualification (`ModuleA.Service` vs
`Service`), and any `typealias` you have not marked with
[`@ZerkAlias`](../Macros%20and%20Markers/ZerkAlias.md).

### Injectable (a type)

A class, struct, enum, or actor marked [`@Injectable`](../Macros%20and%20Markers/Injectable.md).
Without generic arguments the type itself is the key; with them — `@Injectable<Key1, Key2, …>`
— each listed type, typically a protocol, is a key. The declaration carrying the attribute
does not have to *be* the key: it is only where the providers live, which is how a type
from another module joins the graph. See [Registering foreign types](../Features/ForeignTypes.md).

### Value

A declaration marked [`@InjectableValue`](../Macros%20and%20Markers/InjectableValue.md) —
on a variable the declared type is the key and the body becomes the injected value:

```swift
@InjectableValue
var timeout: TimeInterval { 30 }
```

The two are separate markers because they are different things. A type is **built** by a
provider and matched by its key, so one of them wins `inject()`. A value is **read** from a
declaration and matched by key *and name* together — nothing about `inject()`, `primary:`,
or `@InjectableProviding` applies to it. `@InjectableValue` on a *type* is an error naming
the replacement — `@Injectable`, or `@InjectableValues` to sweep its static members. The
other direction is not an error but a different registration: `@Injectable` on a var or func
registers the type that declaration *produces* (see [Provider](#provider)). Matching by name
is what stops two unrelated `String` values from being interchangeable.

### Provider

A way to build a key. Three shapes carry that role: an initializer, a `static` factory
function, and an `@Injectable` declaration itself — a global or `static` var or func, whose
produced type is the key and whose declaration is the provider. The first two are marked
with [`@InjectableProviding`](../Macros%20and%20Markers/InjectableProviding.md);
`@InjectableProviding<Key>` binds a provider to one specific key when a type is injectable
under several, and a bare `@InjectableProviding` serves every key the type claims. A key
may have several providers, each generated as its own named member.

### Implicit provider inference

If no provider is marked at all, Zerk infers one from a single initializer, including
synthesized memberwise (structs) and default initializers. Marking any provider suppresses
that inference — declaring one is a deliberate choice, and a bare initializer must not
silently join it. A type with multiple initializers and no marked provider is an error.

### Primary

The provider `inject()` calls. Primacy has **two independent axes**, elected in this order:

1. `@Injectable(primary: true)` — which **type** wins the key, when several types are
   injectable under it.
2. `@InjectableProviding(primary: true)` — which **provider of that type** wins it, when
   that type offers several.

`inject()` is the intersection. The second round runs only for the winning type, so a
losing type's providers are just named members and need no primary. Both flags must be
written as `true`/`false` literals — Zerk reads them from source and cannot evaluate an
expression.

## Generated code

### The `Zerk<Injectable>` namespace

The namespace itself is an empty `public enum Zerk<Injectable> {}`; everything lives in the
generated extensions. The parameter is named `Injectable` and not `Key`, `Value`, or
`Element`, however well those match Zerk's own vocabulary, because it shadows — for the
whole of every generated extension — any module type spelled the same. A developer with
their own `struct Key` would get `cannot convert value of type 'Foo' to expected argument
type 'Key'` in a file they did not write, and renaming the inner parameters does not fix
it. So the name is chosen for **rarity**, not accuracy.

### Generated member

One static member on `extension Zerk<Key>` per provider, named after the factory, the type
an initializer builds, or the declaration — or after whatever `name:`/`typeNamed:` says.
Every one opens with an interjection lookup and then constructs. Members are `internal`
unless the key was exported with `public: true`.

### Member naming

When the name comes from a *type* rather than from a declaration — an initializer-backed
member, `typeNamed:`, or a singleton's storage — the type name is converted to an
identifier by two rules.

A qualification is dropped, because it says where a type lives rather than what it is
called, and `keychain.Store` is not an identifier. And an acronym that begins the name is
lowercased **whole**, per the Swift API Design Guidelines:

| type | member |
|---|---|
| `ApiService` | `apiService` |
| `URLSession` | `urlSession` |
| `HTTPClient` | `httpClient` |
| `UTF8Decoder` | `utf8Decoder` |
| `URL` | `url` |
| `Keychain.Store` | `store` |

The last capital of a leading run usually begins the next word — `URLSession` is `URL` +
`Session`, so the `S` survives. That does not hold when the run is the whole name (`URL`),
when a digit follows it (`UTF8Decoder`), or when a single letter follows rather than a
word, which is how a plural stays intact (`URLs` gives `urls`).

That last one is a heuristic and the single place the rule cannot be exact: nothing in the
spelling separates the plural `URLs` from the two words of `URLId`. It resolves in favour
of the plural, so a type genuinely spelled `URLId` gives `urlid`. Name the member yourself
with [`@Injectable(name:)`](../Macros%20and%20Markers/Injectable.md) if a type lands on the
wrong side of it.

```swift
extension Zerk<ApiServicing> {
    nonisolated static func apiService(baseURL: String = Zerk<String>.baseURL) -> ApiServicing {
        if let interjected = _$interjected(for: \.`apiService`) {
            return interjected
        }
        return ApiService(baseURL: baseURL)
    }

    nonisolated static var apiService: ApiServicing {
        apiService()
    }

    nonisolated static func inject() -> ApiServicing {
        apiService()
    }
}
```

Member names are an **overload set**, not a unique name: two marked initializers are both
named after their type, and the generated overloads are told apart exactly as the
initializers are. The argument-free `static var` beside the function is additional, emitted
only where it can exist and be reached — so that a key path has something to name.

### `inject()`

The entry point for a key, delegating to the primary member. Everything resolved
*implicitly* goes through it: a provider's dependency, an `@injected` argument, an
`@Injected` property. It **omits** resolved parameters from its signature rather than
defaulting them, so above it takes none while `apiService(baseURL:)` defaults one. Effects
propagate, so an effectful chain is reached as `try await Zerk<Key>.inject()`.

## Parameters

### Parametric injection and bubbled parameters

Provider parameters are resolved in this order: a uniquely matching `@InjectableValue` → a
uniquely resolvable injectable key (recursively) → otherwise the parameter is exposed on
the generated member and on `inject(...)` for the caller to supply. That last case is
**parametric injection**.

When a resolved dependency's own provider still needs such a parameter, the requirement
**bubbles** up and becomes a parameter of the consumer's generated member:

```swift
// Holder's provider takes `token: SeededToken`; SeededToken's provider takes `seed: Int`.
nonisolated static func inject(seed: Int) -> Holder {
    holder(token: Zerk<SeededToken>.inject(seed: seed))
}
```

Your own parameters keep their relative order and everything bubbled is appended after
them; two dependencies needing the same name *and* type share one parameter, and two
needing the same name with different types keep their labels and take distinct inner names.
See [`@injectable`](../Macros%20and%20Markers/ParameterMarkers.md) for feeding a bubbled
requirement from a parameter the member already has.

### E, S, A — how each parameter gets its value

The classifier partitions every provider parameter three ways, and the partition is what
decides the member's shape:

| | name | meaning |
|---|---|---|
| **E** | external | nothing in the module resolves it; the caller supplies it |
| **S** | defaulted | resolvable by a plain expression, emitted as a default argument |
| **A** | body-resolved | resolution carries effects or crosses an isolation domain, so it happens in the body and contributes `async`/`throws` |

`await` cannot appear in a default argument at all, which is *why* A exists. When a
provider has any A parameters the member splits in two — an explicit variant carrying the
interjection lookup and the construction, and a resolving variant that resolves and
delegates, inheriting the merged effects. See [Concurrency](../Features/Concurrency.md).

## Values

### Copied vs. referenced

By default a value's body is *copied* into the generated member, which then never reads the
original — so a later write to the source is invisible to injection. Pass `.referenced` to
read through to the declaration instead, which is what you want for anything updated at
runtime:

```swift
enum Settings {
    @InjectableValue(.referenced)
    nonisolated(unsafe) static var baseURL: String = "api.example.com"
}

Settings.baseURL = "staging.example.com"
Zerk<String>.baseURL        // "staging.example.com" — follows the source
Zerk<String>.baseURL = "x"  // writes back to Settings.baseURL
```

A settable source produces a settable member; a `let` or a get-only computed property stays
read-only. The source must be at least `internal`, since the generated file has to see it —
a `private` value can only be copied. The default is `.copied`, and `valueInjectionMethod`
in `ZerkSettings.json` changes it globally.

## Generic keys

### Key shape

The key a *generic* registration is filed under: the base name plus its arity with the
arguments holed out, so `Cache<String>` and `Cache<Int>` share the shape `Cache<#0>`. A
`struct Cache<E>` cannot file under `Cache<E>` — one family would land under as many keys
as there are ways to spell the parameter — nor under the bare `Cache`, which is not a type
and would collide with a non-generic `Cache`. A dependency looks up **exact first, then
shape**, so a concrete `Cache<String>` registration beats a generic one, the same choice
Swift's own overload resolution makes. The hole is `#` because a shape must not be
writable: SE-0315 placeholders make `Cache<_>` a key a real declaration can produce.

### Erased vs. parameterized existential keys

Both come from a generic type registered under a protocol key, and the same attribute means
opposite things:

| you write | key | resolved as |
|---|---|---|
| `@Injectable<any P>` | `any P`, parameters erased | `Zerk<any P>.inject(1, "a")` |
| `@Injectable<any P>(parameterized: true)` | `any P<X, Y>` | `Zerk<any P<Int, String>>.inject(1, "a")` |

An **erased** key throws the specialization away — every parameter has to arrive as an
argument the caller supplies, and what comes back is `any P`. A **parameterized
existential** key gives the protocol's primary associated types the type's own parameters,
so the specialization survives into the key. It has to be asked for, because the other
reading is legal too. One practical difference: an erased key is concrete and keeps its
[interjection point](#interjection-point), while a parameterized existential has none — an
existential conforms to nothing, so it is reachable by key only, with
`#Interject<any Boxable<Int, String>>(with:)`. See [Generics](../Features/Generics.md).

## Testing

### Interjection point

A `Void` property the plugin declares on `Zerk<Key>.Interjection`, one per generated
member, named — via a raw identifier — verbatim after that member's signature:

```swift
extension Zerk<ApiServicing>.Interjection {
    nonisolated var `apiService`: Void {}
}
```

It exists only so a key path can name it: `#Interject(\.apiService, with: MockApi())`. A
point is named as short as the key allows — the bare name for a name used once, Swift's
selector form (`` \.`loader(store:)` ``) for overloads, and the full form
(`` \.`loader(store: Disk)` ``) only where overloads differ solely by parameter type.
Because the point is a real declaration, a renamed provider makes the interjection a
*compile error* rather than something that silently stops applying.

### Injection scope

A named lifetime, written `InjectionScope("session")`. An injectable marked
`@Scoped(.session)` is built once and handed back until `Zerk.reset(.session)` drops it, at
which point the next resolution builds a fresh one. The name is the identity, whoever
declared the value — which is what lets an app reset a scope a feature module declared. It
is the middle of Zerk's three lifetimes: one instance per resolution by default,
`@Scoped` until a reset, `@Singleton` for the process. See
[`@Scoped`](../Macros%20and%20Markers/Scoped.md).

Unrelated to **interjection scope** below, despite the shared word. That one is about test
isolation; this one is about how long an instance is kept. They never interact.

### Interjection scope

The set of interjections in force for the current task. `ZerkInterjector` is a class held
in a task local, so `#Interject` can add to the set mid-test without wrapping everything
after it; isolation comes from each test getting its own instance. The `.zerk` trait from
`ZerkTesting` opens one per test — `isRecursive`, so a suite-level trait scopes each test
rather than the suite — which is what lets tests interject the same key in parallel without
seeing each other. Outside a scope `#Interject` **traps** rather than leaking into whatever
runs alongside; the one exception is a SwiftUI preview, where the process genuinely is the
scope. See [Scopes](../Testing/Scopes.md).

---

[← Table of contents](../TableOfContents.md)

**See also:** [Quick start](QuickStart.md) · [@Injectable](../Macros%20and%20Markers/Injectable.md) · [@InjectableValue](../Macros%20and%20Markers/InjectableValue.md) · [@InjectableProviding](../Macros%20and%20Markers/InjectableProviding.md) · [Generated code](../Plugin/GeneratedCode.md) · [Testing with interjection](../Testing/Interjection.md)
