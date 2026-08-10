# Limitations

What Zerk cannot do, and why. Most of it follows from one fact: the plugin reads syntax and never resolved types. The rest are rules the graph enforces so the generated file is unambiguous.

## What the plugin can read

### Syntax-level resolution

The codegen parses source; it does not type-check.

Spellings Swift treats as one type *are* unified into one key, because that much is decidable from syntax: `[T]`/`Array<T>`, `[K: V]`/`Dictionary<K, V>`, `T?`/`T!`/`Optional<T>`, `()`/`Void`, `(T)`/`T`, `A & B`/`B & A`, and `P`/`any P`. Canonicalization nests, so `[String]?` and `Optional<Array<String>>` are the same key.

What it cannot unify needs real type resolution, and stays distinct: module qualification (`ModuleA.Service` vs `Service`), and any `typealias` you have not marked with `@ZerkAlias` — the plugin cannot see through an alias on its own, which is exactly why that macro exists. A provider parameter like `seed: Int` is likewise indistinguishable from an injectable dependency except by whether a matching injectable exists.

`any` is a special case. Zerk cannot tell a protocol from a superclass or a struct, and `any` is only legal on an existential — so keys *match* with `any` stripped, but the generated file emits the spelling you wrote. If one declaration says `P` and another `any P`, they are one key and `any P` is what gets emitted.

### Module-scoped

Auto-resolution only sees the current module. `@Injectable(public: true)` makes a key's generated members public so another module can call them manually, but the consuming module cannot auto-resolve a foreign key: its plugin has no way to know that key's effects or isolation. Forward it explicitly with an `@InjectableValue` if you want it in the graph.

A target that declares no injectables needs no plugin and can still use `@Injected`: exporting a key publicizes its members, so it can resolve the primary with a bare `@Injected` or name one with `@Injected(\.staging)`. Without `public: true`, generated members are `internal` and invisible across the boundary.

### Conformance is the compiler's to check, not Zerk's

`@Injectable<Key>` takes your word for it. The generated `inject()` returns `Key` and builds your type, so a type that does not actually conform fails there — `return expression of type 'Store' does not conform to 'Storing'`, naming both. Zerk used to check the inheritance clause itself and refused three correct spellings for it: a conformance added in an extension, one inherited transitively, and `Box<X, Y>: Boxable<X, Y>`, which is legal and genuinely conforms.

### Global actor detection is heuristic

`@MainActor` is recognized exactly; any other attribute ending in `Actor` is assumed to be a global actor. A custom global actor named otherwise, or isolation inherited through a conformance, is invisible to the plugin — annotate it with `@Isolated<A>`.

### Ambient isolation is restated, not read

The plugin cannot see `SWIFT_DEFAULT_ACTOR_ISOLATION`, so `ZerkSettings.json` has to agree with it. When they disagree Zerk infers the wrong provider isolation and the generated code fails to compile. The failure is loud and immediate, but the file is load-bearing rather than advisory.

### `@Isolated<A>` is unverified

It states what the compiler already believes; Zerk cannot check that claim and will generate code matching whatever you wrote.

## Rules the graph enforces

### A key may have many providers; exactly one of them backs `inject()`

When several types claim a key, one needs `@Injectable(primary: true)`. When the winning type has several providers for that key, one needs `@InjectableProviding(primary: true)`. Unresolved ambiguity is a build error — but only for the type that actually wins the key; a losing type's providers are just named members and need no primary.

### Circular dependencies

Circular dependencies are rejected with the cycle path in the error (`Circular dependency detected: Cyc1 -> Cyc2 -> Cyc1`). Break cycles manually (e.g. inject a factory or make one edge parametric).

### Generated member names must be unique per key *per signature*

Providers may share a member name when their parameters differ — two marked initializers both generate `Zerk<Key>.loader(...)`, told apart exactly as the initializers are. Two that agree on name *and* parameters (e.g. a `Service` in two files, both argument-free) collide; rename the type, rename the factory, or give one of them `@InjectableProviding(name:)`. Note that this cuts both ways — `typeNamed:` on two factories returning the same type makes them collide where their own names did not.

### Generic injectables

Generic injectables have their own rules — three ways to register one, and what each can and cannot do. See [Generics](../Features/Generics.md).

### `@Singleton` constraints

Reference types only; provider must be synchronous and non-throwing; no external arguments; no dependency in a different isolation domain, since resolving one would need `await`; exactly one provider per key, and the *same* provider across every key the type claims. A singleton injectable under several keys must be built by an initializer or by a factory returning the concrete type — its one instance is stored once and read through every key.

### Referenced values must be visible to the generated file

That file is a separate file in the same module, so `private` and `fileprivate` sources cannot be referenced — only copied. A mutable `static var` also has to be legal Swift 6 global state in its own right (`nonisolated(unsafe)`, or actor-isolated); Zerk mirrors whatever isolation you give it but does not launder it.

### `@Injected` cannot resolve async, throwing, or cross-domain chains

Use `try await Zerk<Key>.inject()` manually (or an `@injected` parameter). For lazy resolution, use a plain `lazy var = Zerk<Key>.inject()`; there is no `@LazyInjected` macro.

## Testing, and the output itself

### Interjection is keyed by generated member signature

A point is named after the member it stands in for, so anything that renames the member — renaming an injectable type, renaming an `@InjectableProviding` factory, or adding `typeNamed:`/`name:` to one — makes the interjection a *compile error*, caught rather than silently ignored. Two overloads of one name get separate points, since the name carries the parameters.

### Interjection does not short-circuit resolution

A member's dependencies are resolved before the lookup runs, so an interjected value still builds its real dependency subtree first.

### Generated code is per-build

The plugin output lives in the build directory (`Zerk.generated.swift`). Never edit it; regenerate by building.

---

[← Table of contents](../TableOfContents.md)

**See also:** [Diagnostics](Diagnostics.md) · [How it works](HowItWorks.md) · [Generated code](GeneratedCode.md) · [Settings](Settings.md) · [Generics](../Features/Generics.md) · [Concurrency](../Features/Concurrency.md) · [Key aliases](../Macros%20and%20Markers/ZerkAlias.md) · [`@Singleton`](../Macros%20and%20Markers/Singleton.md) · [Interjection](../Testing/Interjection.md)
