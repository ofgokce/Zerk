# Parameter markers

Four lowercase markers — `@injected`, `@autoinjected`, `@noninjected`, `@injectable` — say
what happens to a single parameter. This page covers what each one means, how they differ
from one another, and the rules by which parameters bubbled up from a dependency's provider
are ordered and combined.

The names are similar and the distinctions are the thing readers get wrong, so start here:

| Marker | Means | Applies to |
|---|---|---|
| `@injected` | Resolve this parameter, and omit it from a generated overload of the enclosing member | Any initializer or method parameter |
| `@autoinjected` | Resolve this provider parameter — and switch the provider to explicit mode, where nothing else is resolved | A parameter of an [`@InjectableProviding`](InjectableProviding.md) provider |
| `@noninjected` | Never resolve this provider parameter; it is always the caller's | A parameter of an [`@InjectableProviding`](InjectableProviding.md) provider |
| `@injectable` | This parameter feeds a requirement bubbled up from a resolved dependency | Either path |

There are two resolution paths, and the markers split along them. `@injected` generates an
overload of the *enclosing member* for direct construction. `@autoinjected` and
`@noninjected` shape the `inject(...)` member Zerk generates for an
[`@Injectable`](Injectable.md) key. `@injectable` works on both, because bubbling is shared
behaviour. `@injected` and `@autoinjected` are unrelated and compose — a parameter may
carry both, and does both things.

## Why property wrappers rather than macros

All four are property wrappers, not macros: Swift attached macros cannot be applied to
parameters, so a wrapper is the only way per-parameter marking is legal Swift. Each is
semantically inert — it performs no resolution and supplies no default. Because it is an
implementation-detail wrapper (SE-0293, `init(wrappedValue:)` only), call sites of the
original member are completely unaffected. The build plugin does all detection, resolution,
and code generation.

The lowercase names are deliberate. `@Injected` is the property macro, `@injected` the
parameter marker — Swift identifiers are case-sensitive, so the two never collide, and the
lowercase spelling reads like a built-in parameter attribute such as `@escaping`. Use
[`@Injected`](Injected.md) for properties; `@injected` for parameters.

## `@injected` — parameter injection

Marks an initializer or method parameter; the build plugin generates an overload with every
marked parameter omitted and filled via `Zerk<Key>.inject()`. When the resolved dependency's
own provider still needs arguments, those bubble up onto the overload — see `@injectable`
below to feed one from a parameter the member already has:

```swift
final class AuditTrail {
    init(@injected logger: Logger, label: String) { ... }
}

AuditTrail(label: "audit")                    // generated overload, logger injected
AuditTrail(logger: myLogger, label: "manual") // original init, untouched
```

```swift
// generated:
extension AuditTrail {
    nonisolated convenience init(label: String) {
        self.init(logger: Zerk<Logger>.inject(), label: label)
    }
}
```

Class inits get a `convenience` overload; structs, actors, and enums get a plain extension
init; methods get a delegating overload:

```swift
final class C {
    init(@injected logger: Logger, label: String) { ... }
    func send(@injected logger: Logger, payload: String) -> Int { ... }
}

// generated:
// extension C {
//     nonisolated convenience init(label: String) {
//         self.init(logger: Zerk<Logger>.inject(), label: label)
//     }
//
//     nonisolated func send(payload: String) -> Int {
//         send(logger: Zerk<Logger>.inject(), payload: payload)
//     }
// }
```

### Methods declared in an extension

A method in an `extension` is marked the same way, and its overload lands in an extension of
the same type:

```swift
extension Service {
    func run(@injected repo: Repo, id: Int) -> Int { ... }
}

// generated:
// extension Service {
//     nonisolated func run(id: Int) -> Int {
//         run(repo: Zerk<Repo>.inject(), id: id)
//     }
// }
```

Each extension gets **its own** generated block, carrying that extension's `where` clause, so
the overload lands somewhere its body is legal — two extensions of one type with different
constraints stay two blocks:

```swift
extension Cache where E: Equatable {
    func run(@injected repo: Repo, item: E) -> E { ... }
}

// generated:
// extension Cache where E: Equatable { ... }
```

A **nested** type keeps its qualification: a member of `extension Outer.Inner`, or of a type
declared inside `extension Outer`, generates `extension Outer.Inner` rather than
`extension Inner`.

The **extended type must be visible to the generated file**, which is a separate file: an
extension of a `private` or `fileprivate` type is refused. An extension's own modifiers say
nothing about the type it extends, so this is checked against the type's declaration rather
than the extension's.

An **initializer** in an extension is refused. The generated overload has to delegate with
`self.init(…)`, and that must say `convenience` when the extended type is a class and must not
when it is a struct — a fact about a type Zerk may never see, since an extension can extend a
type from another module. Declare the initializer on the type itself, or resolve the dependency
in its body.

### Global functions

A top-level `func` is marked the same way, and gets a file-scope overload rather than one in
an extension:

```swift
@Injectable
final class Logger { init() {} }

func audit(@injected logger: Logger, label: String) {}
```

```swift
nonisolated func audit(label: String) {
    audit(logger: Zerk<Logger>.inject(), label: label)
}
```

Everything below applies to it unchanged — access level, generics, bubbling, isolation, and
the rule that two overloads may not collide.

A **local** function is not a global: one declared inside a body or an accessor is skipped,
because nothing outside the file could call an overload of it.

### Constraints

- The marked parameter's type must be resolvable in the module — `@Injectable`, with
  whatever arguments its provider needs bubbling onto the overload.
- No default values on marked parameters.
- No variadic or `inout` parameters — and no variadic *unmarked* parameter either, since the
  generated overload has to pass those on and Swift cannot pass a variadic on.

An unmarked parameter is otherwise reproduced as written: its label, its specifier, and its
own default value all carry onto the overload.
- No generic types or generic members. In an *extension* of a generic type the rule is
  narrower and applies to the marked parameter rather than the member: a concrete key
  resolves there as anywhere, but a marked parameter naming one of the type's own
  parameters cannot, since nothing can register one.
- The member must be at least `internal` — the generated overload lives in a separate
  generated file and cannot call private or fileprivate members.

Async or throwing chains are allowed — and so are cross-domain ones, which merge in as
`async` — so the generated overload becomes `async`/`throws` accordingly. This is the one
injection path that supports effectful construction:

```swift
// Logger's provider is `init() async throws`:
extension AuditTrail {
    nonisolated convenience init(label: String) async throws {
        self.init(logger: try await Zerk<Logger>.inject(), label: label)
    }
}
```

See [Concurrency](../Features/Concurrency.md) for how effects propagate through a chain.

## `@autoinjected` — states which provider parameters Zerk resolves

By default a provider's parameters are auto-resolved wherever Zerk can, and the rest become
parameters of the generated member. That is convenient but inferred: adding a type to the
graph can turn a caller-supplied parameter into a resolved one without anyone touching the
provider.

Marking any parameter switches that provider to **explicit mode** — marked parameters are
resolved, unmarked ones are always the caller's, and a marked parameter Zerk cannot resolve
is a build error on that parameter's line:

```swift
@Injectable
final class Checkout {
    @InjectableProviding
    init(@autoinjected payments: PaymentServicing, orderID: String) { ... }
}

// generated: `payments` resolved, `orderID` left to the caller
// static func inject(orderID: String) -> Checkout
```

With nothing marked, the provider keeps the inferred behaviour, so this is opt-in per
declaration. It applies to an implicitly adopted initializer too. A marked parameter whose
own provider needs arguments is still resolved, with those arguments bubbling up to
`inject(...)`.

The error for an unresolvable marked parameter names both ways out:

```
error: @autoinjected parameter 'payments' cannot be resolved: 'PaymentServicing' is not
injectable in this module. Declare it @Injectable, or drop @autoinjected and pass it in.
```

`@autoinjected` is distinct from `@injected`, which generates an overload of the *enclosing
member*. They compose — `@injected @autoinjected` does both:

```swift
@Injectable
final class Both {
    @InjectableProviding
    init(@injected @autoinjected foo: Foo, label: String) { ... }
}

// generated: the provider path
// static func inject(label: String, value: Value) -> Both
// and the direct-construction overload
// extension Both {
//     nonisolated convenience init(label: String, value: Value) {
//         self.init(foo: Zerk<Foo>.inject(value: value), label: label)
//     }
// }
```

### An inert mark warns, it does not fail

Marking a parameter somewhere Zerk never resolves — a second initializer, an ordinary
method, a static function without `@InjectableProviding`, or a type that is not
`@Injectable` — is a **warning**, not an error. The marker is inert there rather than wrong,
so the build still succeeds; but a mark being silently ignored is the one thing explicit
resolution exists to prevent, so it is never passed over in silence.

```
warning: @autoinjected has no effect here: this initializer is not 'Second's provider.
Mark it @InjectableProviding, or move the marked parameters to the provider.

warning: @autoinjected has no effect here: 'Inert' is not @Injectable, so it has no
provider whose parameters Zerk resolves.
```

A function is never a provider: [`@InjectableValue`](InjectableValue.md) does not apply to one at all, and a `static func` without `@InjectableProviding` is not something Zerk resolves — so a marker on either is inert and reported as such.

## `@noninjected` — keeps a parameter out of resolution

The inverse of `@autoinjected`, for a provider that is mostly happy inferring: mark the
exceptions rather than every parameter.

```swift
@InjectableProviding
init(payments: PaymentServicing, @noninjected retries: Int) { ... }
// `retries` stays on the generated member even though an
// `@InjectableValue var retries: Int` exists in the module
```

```swift
// generated:
// static func inject(retries: Int) -> Checkout
```

A provider that marks something `@autoinjected` already excludes everything unmarked, so
`@noninjected` is redundant there — it is accepted without complaint, since stating every
parameter's intent is a fair style. Marking one parameter both ways is a contradiction and
is reported:

```
error: 'retries' is marked both @autoinjected and @noninjected. Keep the one you meant.
```

## `@injectable` — feeds one of this member's parameters into a dependency Zerk resolves for it

When a resolved dependency's own provider needs arguments, those bubble up and become
parameters of the generated member. If the member already declares a parameter that would
satisfy one, `@injectable` says so, and the single parameter serves both:

```swift
@Injectable
final class Foo {
    init(value: Value) { ... }
}

final class Bar {
    init(@injected foo: Foo, @injectable value: Value) { ... }
}

// generated:
// extension Bar {
//     convenience init(value: Value) {
//         self.init(foo: Zerk<Foo>.inject(value: value), value: value)
//     }
// }
```

Without it the same `value` would be declared twice — once as `Bar`'s own parameter, once
bubbled up for `Foo` — which is a build error rather than a silent merge, so sharing is
always something you wrote down. Matched by name *and* type, the rule an
[`@InjectableValue`](InjectableValue.md) already follows; a differently named parameter does
not match and the requirement bubbles on its own. Works with `@injected` on any member and
with `@autoinjected` on a provider.

The collision the marker resolves is reported like this:

```
error: Resolving 'foo' needs 'value: Value', which collides with 'Collide's own 'value'
parameter. Mark it @injectable to feed the same value to both.
```

On a provider it reads the same way:

```swift
@Injectable
final class Bar {
    @InjectableProviding
    init(@autoinjected foo: Foo, @injectable value: Value) { ... }
}

// generated:
// static func inject(value: Value) -> Bar
//     bar(foo: Zerk<Foo>.inject(value: value), value: value)
```

## How bubbled parameters are ordered and combined

The rules are the same on both paths:

- Your own parameters keep their relative order, and everything bubbled is appended **after**
  them, in the order of the parameters that pulled them in.
- Two dependencies needing the same parameter *name and type* share one parameter, however
  many asked for it.
- Two needing the same name but **different** types keep the label they were declared with
  and take distinct inner names, since a signature cannot bind one name twice:

```swift
@InjectableProviding
init(@autoinjected a: FooA, @autoinjected b: FooB) {}   // FooA needs value: ValueA, FooB needs value: ValueB

// static func inject(value valueA: ValueA, value valueB: ValueB) -> Consumer
```

The suffix is the parameter that pulled the requirement in. The same renaming applies when a
bubbled name would clash with one of your own parameters of a different type — yours keeps
its name.

Ordering, on both paths at once:

```swift
final class Overload {
    init(first: String, @injected foo: Foo, last: String) {}
}

@Injectable
final class Provider {
    @InjectableProviding
    init(first: String, @autoinjected foo: Foo, last: String) {}
}

// convenience init(first: String, last: String, value: Value)
// static func inject(first: String, last: String, value: Value) -> Provider
```

Bubbled parameters follow the order of the parameters that pulled them in:

```swift
final class Bar {
    init(@injected foo: Foo, mid: String, @injected qux: Qux) {}
}

// convenience init(mid: String, value: Value, extra: Extra)
```

Sharing, when name and type agree:

```swift
// FooA and FooB both need `value: Value`
// static func inject(value: Value) -> Consumer
//     consumer(a: Zerk<FooA>.inject(value: value), b: Zerk<FooB>.inject(value: value))
```

And the clash between a bubbled name and one of your own parameters, where only the bubbled
one can move:

```swift
@Injectable
final class Clash {
    @InjectableProviding
    init(@autoinjected foo: Foo, @noninjected value: String) {}
}

// static func inject(value: String, value valueFoo: Value) -> Clash
//     clash(foo: Zerk<Foo>.inject(value: valueFoo), value: value)
```

---

[← Table of contents](../TableOfContents.md)

**See also:** [`@Injected`](Injected.md) · [`@Injectable`](Injectable.md) · [`@InjectableProviding`](InjectableProviding.md) · [`@InjectableValue`](InjectableValue.md) · [Injected examples](../Getting%20Started/InjectedExamples.md) · [Terminology](../Getting%20Started/Terminology.md) · [Concurrency](../Features/Concurrency.md) · [Generics](../Features/Generics.md) · [Generated code](../Plugin/GeneratedCode.md) · [Diagnostics](../Plugin/Diagnostics.md) · [Limitations](../Plugin/Limitations.md)
