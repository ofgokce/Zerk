# @Injectable

`@Injectable` registers a **type** with the dependency graph. This page is the reference for every form it takes: the keys it claims, the two arguments that decide which type wins a key and who may see it, the form that goes on a global or static declaration, and the declarations it refuses.

## What it does

**`@Injectable` / `@Injectable<Key1, Key2, …>`** — marks a class, struct, enum, or actor as injectable. Without generic arguments the type itself is the key; with them, each listed type (typically a protocol) is a key.

Every key needs a way to be built — see [@InjectableProviding](InjectableProviding.md).

The macro is semantically inert: it validates and expands to nothing. Registration happens in the build plugin. What the macro adds is the subset of errors decidable from the declaration alone — a key claimed twice, a key with no provider at all, an `@InjectableProviding<Key>` with no matching `@Injectable<Key>` — reported at the declaration instead of from generated code you did not write.

Conformance is deliberately *not* among them. Reading syntax, Zerk sees only what the declaration itself lists — not a conformance added in an extension, inherited transitively, or declared in another module — so checking it refused code that was correct. The compiler settles the same question on the generated member, with both real types named.

## Keys

A bare `@Injectable` keys on the type. A generic argument list replaces that with the types listed, and a declaration may carry several attributes, one per key, or name several in one:

```swift
@Injectable<Storing, Caching>
final class Store: Storing, Caching { init() {} }

// Zerk<Storing>.inject()  and  Zerk<Caching>.inject()
```

Every other argument rides on the attribute that names the key, so a type injectable under several can answer differently for each — see `primary:` and `public:` below.

`@Injectable<Key>` does not require the annotated declaration to *be* `Key`. The declaration is only where the providers live; the key is what they build — which is how a type from another module joins the graph. [Registering a type you do not declare](../Features/ForeignTypes.md) is the guide to that.

## `primary:` — which type wins the key

**`@Injectable(primary:)`** — when several *types* are injectable under the same key, marks the one `inject()` should build. Exactly one must claim it; leaving the key contested is a build error. The others are still generated as named members (`Zerk<Loading>.mockLoader`), they simply do not win the key.

```swift
@Injectable<Loading>(primary: true)
final class LiveLoader: Loading { init() {} }

@Injectable<Loading>
final class MockLoader: Loading { init() {} }

Zerk<Loading>.inject()      // LiveLoader
Zerk<Loading>.mockLoader    // still available
```

The two `primary` flags are independent axes: `@Injectable(primary:)` picks the winning **type**, [`@InjectableProviding(primary:)`](InjectableProviding.md) picks the winning **provider within that type**. `inject()` is the intersection. A type that loses the key never needs a primary among its own providers.

Like every Zerk attribute it applies per key, so `@Injectable<A>(primary: true) @Injectable<B>` claims `A` only. It is a *type*-only argument: a value is the sole provider for its key, so `primary` on one is an error.

## `public:` — exporting a key

**`@Injectable(public:)`** — makes the generated members `public`, so other modules can resolve the key. That covers `inject()` *and* the named members, so a consuming module can also reach one specific provider with `@Injected(\.staging)`. Zerk generates `internal` members by default, which keeps a module's graph its own business.

Like `primary`, it rides on the attribute that names the key, so a type injectable under several can export some of them:

```swift
@Injectable<Storing>(public: true)
@Injectable<Caching>
public final class Store: Storing, Caching { ... }

// Zerk<Storing>  members are public
// Zerk<Caching>  members stay internal
```

Unlike `primary`, it applies to values too, and [`@InjectableValues(public:)`](InjectableValue.md) exports a whole constants namespace at once. Stating `public:` on a member is what overrides the sweep; a bare `@Injectable` says nothing about access and inherits it.

The key type itself must be `public` — a public member cannot expose an internal type — otherwise the request is dropped with a warning. A value's *own* declaration may stay internal, since only the key appears in the generated member's signature and the accessor reads the source from its body. A [`@Singleton`](Singleton.md)'s shared storage stays private either way; only its getter is exported.

Exporting a key makes its members visible; it does not tell the consuming module the key exists. That is [`@ImportedInjectable`](ImportedInjectables.md)'s job.

## On a global or static declaration

`@Injectable` on a **global or static** var or func registers the type it *produces*, with the declaration as its provider:

```swift
@Injectable
var urlSession: URLSession { URLSession(configuration: .default) }
```

The key is the declared or returned type unless a generic argument states one, and the member gets an interjection point like any other. A function's parameters are dependencies like any provider's; a generic function registers exactly as a generic type does, under the family, with the member binding it per call:

```swift
@Injectable(typeNamed: true)
func makeBox<X, Y>(x: X, y: Y) -> Box<X, Y> { … }

Zerk<Box<Int, String>>.box(x: 1, y: "a")
```

[Registering a type you do not declare](../Features/ForeignTypes.md) covers this form in full, alongside the provider-type alternative.

### Naming the member

The member takes the declaration's own name. Two arguments change that, and they are alternatives — stating both is an error:

| written | key | member |
|---|---|---|
| `@Injectable var urlSession: URLSession` | `URLSession` | `urlSession` |
| `@Injectable<URLSessionProtocol> var urlSession: URLSession` | `URLSessionProtocol` | `urlSession` |
| `@Injectable(typeNamed: true) var dummyName: URLSession` | `URLSession` | `urlSession` |
| `@Injectable(name: "mainSession") var dummyName: URLSession` | `URLSession` | `mainSession` |
| `@Injectable<URLSessionProtocol>(typeNamed: true) var dummyName: URLSession` | `URLSessionProtocol` | `urlSession` |

`typeNamed:` reads the **produced type**, not the key — the last row is named from `URLSession`, not from `URLSessionProtocol`. `name:` takes a string literal; Zerk reads syntax and cannot evaluate an expression or an interpolation.

`typeNamed:` and `name:` exist on `@InjectableProviding` too, and mean the same thing there.

### Where it may go

Global, or `static` on a type. An instance member is refused — the generated file calls the declaration directly and has no instance to call it on — and so is anything below `internal`, since that file cannot see it. A **global** is reached through a generated private forwarding function rather than by name: inside `extension Zerk<Key>` an unqualified `urlSession` resolves to the member being defined, so reading it directly would recurse. A static member needs none; `Container.session` is already unambiguous.

A function needs a return type, and a property a single named binding with an explicit type — the type is the key, and a syntax-only plugin cannot infer one.

## `parameterized:` — a generic type under an existential key

**`@Injectable<any P>(parameterized: true)`** registers a generic type under a **parameterized existential** key: the type's own parameters become the protocol's primary associated types.

```swift
protocol Boxable<X, Y> { associatedtype X; associatedtype Y }

@Injectable<any Boxable>(parameterized: true)
struct Box<X, Y>: Boxable {
    @InjectableProviding init(_ x: X, _ y: Y) { … }
}

Zerk<any Boxable<Int, String>>.inject(1, "a")
```

It has to be asked for, because the same attribute without it means the opposite — erase the parameters into a plain `any Boxable` — and both are legal. The key cannot be written out in full: an attribute is resolved outside the declaration's scope, so `@Injectable<any Boxable<X, Y>>` is rejected by Swift itself with `'X' does not conform to 'Copyable'`. It is the only argument that exists solely on the keyed form, since there is no key to parameterize otherwise, and the generated members carry an `@available` attribute — parameterized existentials are iOS 16 / macOS 13 and later.

[Generics](../Features/Generics.md) has the three registration shapes side by side and what each entails.

## What it refuses

**`@Injectable` on an `extension` is refused**, with a message pointing at a provider type instead. An extension is not a declaration — it states no generic parameters of its own, so `extension Wrapper` cannot say whether `Wrapper` is generic, and for a foreign type there is no way to find out. It also has no initializer to adopt implicitly, and a `where` clause would make its providers conditional on something the key cannot express.

**An injection method is refused.** There is no `@Injectable` overload taking one, so `@Injectable(.referenced)` is a Swift error before Zerk sees it. The build plugin reads syntax rather than resolving overloads, so it reports the useful version alongside: the injection method applies to values only, since a type is built by a provider rather than read from a declaration and so has nothing to copy or reference. See [`@InjectableValue`](InjectableValue.md).

**`primary:` on a value is refused**, for the reason above: a value is the sole provider for its key, so there is nothing to be primary over.

**`@InjectableValue` on a class, struct, enum, or actor is refused**, with a message naming `@Injectable` as the replacement — or `@InjectableValues` to sweep up the type's static properties. The two markers are separate because they are different things: a type is *built* by a provider and matched by its key, a value is *read* from a declaration and matched by key *and* name together. Use [`@InjectableValue`](InjectableValue.md) for configuration the graph reads, and `@Injectable` for a dependency the graph builds.

## Arguments are read, not evaluated

Both `primary` and `public` must be written as `true`/`false` literals — Zerk reads them from source and cannot evaluate an expression. So must `typeNamed:` and `parameterized:`, and `name:` must be a string literal. This is the same constraint that runs through the whole design: the plugin reads syntax, never resolved types.

## Every overload

| written | means |
|---|---|
| `@Injectable` | the type itself is the key |
| `@Injectable<each T>` | each listed type is a key |
| `@Injectable(public:)` | exports the key's generated members |
| `@Injectable(primary:public:)` | claims the key for `inject()` |
| `@Injectable(typeNamed:primary:public:)` | on a declaration: names the member after the produced type |
| `@Injectable(name:primary:public:)` | on a declaration: names the member outright |
| `@Injectable<each T>(parameterized:public:)` | the type's parameters become the key's |
| `@Injectable<each T>(primary:parameterized:public:)` | both at once |

Every form is declared twice — once bare, once with a `<each T>` key list — except `parameterized:`, which exists only in the keyed form, since without a written key there is nothing to parameterize. `primary` and `public` are `false` unless stated.

---

[← Table of contents](../TableOfContents.md)

**See also:** [@InjectableProviding](InjectableProviding.md) · [@InjectableValue](InjectableValue.md) · [@Singleton](Singleton.md) · [@Injected](Injected.md) · [Imported injectables](ImportedInjectables.md) · [Foreign types](../Features/ForeignTypes.md) · [Generics](../Features/Generics.md) · [Generated code](../Plugin/GeneratedCode.md) · [Diagnostics](../Plugin/Diagnostics.md)
