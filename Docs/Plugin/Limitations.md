# Limitations

What Zerk cannot do, and why. Most of it follows from one fact: the plugin reads syntax and never resolved types. The rest are rules the graph enforces so the generated file is unambiguous.

## What the plugin can read

### Syntax-level resolution

The codegen parses source; it does not type-check.

Spellings Swift treats as one type *are* unified into one key, because that much is decidable from syntax: `[T]`/`Array<T>`, `[K: V]`/`Dictionary<K, V>`, `T?`/`T!`/`Optional<T>`, `()`/`Void`, `(T)`/`T`, `A & B`/`B & A`, and `P`/`any P`. Canonicalization nests, so `[String]?` and `Optional<Array<String>>` are the same key.

**Module qualification is unified too, for the modules you name.** `Core.Service` and `Service` are one key whenever [`#ZerkImport(module: "Core")`](../Macros%20and%20Markers/ImportedInjectables.md) is present — which it has to be anyway for the generated file to compile against that module. Two things make that the right boundary: inside a file importing `Core` the spellings are interchangeable by definition, and the short one Zerk emits still resolves, because the generated file imports the same module.

**`Swift` is the one module you never declare.** `Swift.String` and `String` are one key with no `#ZerkImport` at all, because the language implicitly imports `Swift` into every file — the generated one included — so the short spelling always resolves. Nothing else gets that: `Foundation.Date` still needs `#ZerkImport(module: "Foundation")`, which the generated file needs anyway.

A prefix from a module you have *not* imported is left alone. Syntax cannot tell `Outer.Inner` (a nested type) from `Core.Inner` (a module-qualified one), so the imported-module list is the only evidence Zerk has — and stripping without it would both mis-key the dependency and emit a name the generated file could not resolve. Only the leading component goes: `Core.Outer.Inner` keeps its nesting.

What still needs real type resolution, and stays distinct: any `typealias` you have not marked with `@ZerkAlias` — the plugin cannot see through an alias on its own, which is exactly why that macro exists. A provider parameter like `seed: Int` is likewise indistinguishable from an injectable dependency except by whether a matching injectable exists.

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

### `#if` conditions are carried, never evaluated

The plugin is told neither the build configuration nor the active compilation conditions, and SwiftPM caches its result across configurations — so an answer to "is `DEBUG` set?" given during a Debug build would be reused for the Release one. Instead the guard is reproduced in the generated file and the compiler decides. [Conditional compilation](../Features/ConditionalCompilation.md) covers what follows from that; three limits are worth stating here.

**Only clauses of one `#if` are known to be exclusive.** A separate `#if DEBUG` and `#if !DEBUG` are opposites to a reader, but telling so means evaluating `DEBUG` — so they are treated as able to coexist, and a key both claim is reported as ambiguous. Write them as one `#if` / `#else`.

**Branches must agree on what resolving the key costs.** They may build different things; they may not differ in effects, isolation, or the arguments left to the caller, because everything injecting the key resolves it through one `inject()` call emitted for every configuration.

**A `#if` inside an injectable type may not gate its construction.** A conditional initializer or `@InjectableProviding` member would give one type two provider shapes, and the generated member has one signature. A `#if` gating anything else inside a type — a method, a stored property — is not Zerk's business and passes through.

## Rules the graph enforces

### A key may have many providers; exactly one of them backs `inject()`

When several types claim a key, one needs `@Injectable(primary: true)`. When the winning type has several providers for that key, one needs `@InjectableProviding(primary: true)`. Unresolved ambiguity is a build error — but only for the type that actually wins the key; a losing type's providers are just named members and need no primary.

### Circular dependencies

Circular dependencies are rejected with the cycle path in the error (`Circular dependency detected: Cyc1 -> Cyc2 -> Cyc1`). Break cycles manually (e.g. inject a factory or make one edge parametric).

Cycle detection follows one primary per key. Where `#if` clauses give a key a different primary per configuration, it follows the first — so two keys that *both* vary, and whose branches interlock oppositely, can be reported as a cycle that no single configuration actually has. Restructuring to break the reported cycle is the remedy; it has no false-negative counterpart, since a cycle within one configuration is always found.

### Generated member names must be unique per key *per signature*

Providers may share a member name when their parameters differ — two marked initializers both generate `Zerk<Key>.loader(...)`, told apart exactly as the initializers are. Two that agree on name *and* parameters (e.g. a `Service` in two files, both argument-free) collide; rename the type, rename the factory, or give one of them `@InjectableProviding(name:)`. Note that this cuts both ways — `typeNamed:` on two factories returning the same type makes them collide where their own names did not.

### Generic injectables

Generic injectables have their own rules — three ways to register one, and what each can and cannot do. See [Generics](../Features/Generics.md).

### `@Singleton` and `@Scoped` constraints

Reference types only; no external arguments; exactly one provider per key, and the *same* provider across every key the type claims. One injectable under several keys must be built by an initializer or by a factory returning the concrete type — its one instance is stored once and read through every key. Neither can be applied to a generic type: the storage is a static stored property, so there is nowhere to keep one instance per specialization.

An `async` or `throws` provider, or one whose dependency is effectful or lives in another isolation domain, is allowed: the instance moves from a `static let` or a `ZerkScopedBox` into a `ZerkAsyncBox`. What it costs is that *reading* it becomes `async` — including when the construction only throws, since joining the one build is what suspends — and that the instance must be `Sendable`, which the box's `Task` requires. See [Concurrency](../Features/Concurrency.md#kept-instances-that-have-to-await).

### A scope reachable from a nonisolated member must itself be `nonisolated`

Under `SWIFT_DEFAULT_ACTOR_ISOLATION`, `extension InjectionScope { static let session = … }` is isolated to that actor, and the generated box slot for a *nonisolated* `@Scoped` type cannot read it. Zerk pins each slot to its member's isolation, which handles every other combination, but it cannot reach into your scope declaration. Write `nonisolated static let session = InjectionScope("session")` and it holds in all of them; the generated storage carries a comment saying so.

### Zerk cannot tell which scope outlives which

A `@Singleton` capturing a `@Scoped` instance is an error, because a singleton outlives every scope by construction. A `@Scoped(.a)` capturing a `@Scoped(.b)` one is only a **warning**: Zerk knows the scopes differ but has no idea which is reset first, or whether either ever is. `.request` inside `.session` is a bug and `.session` inside `.application` is fine, and nothing in the source distinguishes them.

### Referenced values must be visible to the generated file

That file is a separate file in the same module, so `private` and `fileprivate` sources cannot be referenced — only copied. A mutable `static var` also has to be legal Swift 6 global state in its own right (`nonisolated(unsafe)`, or actor-isolated); Zerk mirrors whatever isolation you give it but does not launder it.

### `@Injected` cannot resolve async, throwing, or cross-domain chains

Use `try await Zerk<Key>.inject()` manually (or an `@injected` parameter). For lazy resolution, use a plain `lazy var = Zerk<Key>.inject()`; there is no `@LazyInjected` macro.

## Testing, and the output itself

### Interjection is keyed by generated member signature

A point is named after the member it stands in for, so anything that renames the member — renaming an injectable type, renaming an `@InjectableProviding` factory, or adding `typeNamed:`/`name:` to one — makes the interjection a *compile error*, caught rather than silently ignored. Two overloads of one name get separate points, since the name carries the parameters.

### Interjection does not short-circuit resolution — except for kept instances

A parameterized member takes its dependencies as *default arguments*, and Swift evaluates those before the body runs. So an interjected value still builds its real dependency subtree first, which matters when a dependency's construction is expensive or has side effects. Interject the dependency too if that is a problem.

A `@Singleton` or `@Scoped` member is the exception, and it falls out of where the construction sits rather than from any special handling: a singleton's subtree is built inside its `static let` initializer, a scoped one inside the closure handed to its box, and the guard returns ahead of both. Interjecting one of those builds nothing at all.

### Generated code is per-build

The plugin output lives in the build directory (`Zerk.generated.swift`). Never edit it; regenerate by building.

---

[← Table of contents](../TableOfContents.md)

**See also:** [Diagnostics](Diagnostics.md) · [How it works](HowItWorks.md) · [Generated code](GeneratedCode.md) · [Settings](Settings.md) · [Generics](../Features/Generics.md) · [Concurrency](../Features/Concurrency.md) · [Conditional compilation](../Features/ConditionalCompilation.md) · [Key aliases](../Macros%20and%20Markers/ZerkAlias.md) · [`@Singleton`](../Macros%20and%20Markers/Singleton.md) · [Interjection](../Testing/Interjection.md)
