# `@Injected`

`@Injected` resolves eagerly when the enclosing value is initialized. This page covers its
four variants, the rules that govern the key it resolves, the key-path form and the members
it can reach, the chains it cannot resolve at all, and
[`@InjectedDynamically`](#injecteddynamically) — the same thing resolved per access instead of once.

`@Injected` (uppercase) is the property macro. `@injected` (lowercase) is a *parameter*
marker and a different thing entirely — see [Parameter markers](ParameterMarkers.md). The
case difference is deliberate, so the two never collide.

## The one Zerk macro that generates code

`@Injectable`, `@InjectableProviding`, `@Singleton`, and `@Isolated` expand to *nothing* —
they exist so the plugin has an attribute to read. `@Injected` is the one macro that
generates code, because the expression it needs (`Zerk<Key>.inject()`) depends on nothing
but the property's own type. No whole-module view is required, so the macro can do it alone.

`@Injected var apiService` expands to a stored property whose default value is
`Zerk<ApiServicing>.inject()`:

```swift
struct FeedViewModel {
    @Injected
    var apiService: ApiServicing
}

// The macro adds a peer beside the property:
private var _$zerk_injection_apiService: ApiServicing = Zerk<ApiServicing>.inject() {
    @storageRestrictions(initializes: apiService)
    init(initialValue) {
        apiService = initialValue
    }
    get {
        apiService
    }
}
```

The peer uses `@storageRestrictions(initializes:)` (SE-0400) so it *initializes* the
original property rather than shadowing it. That is what keeps a value passed to the
memberwise initializer winning over the injected default.

## Variants

```swift
@Injected var service: ApiServicing                 // Zerk<ApiServicing>.inject()
@Injected(seed: 100) var token: SeededToken         // forwards args to inject(seed:)
@Injected(\.cached) var loader: Loading             // names a member instead of the primary
@Injected<LiveService> var s: Serving               // resolve this key, store it as that type
```

| Written | Key resolved |
|---|---|
| `@Injected` | the property's type |
| `@Injected<Foo>` | `Foo` |
| `@Injected(\.member)` | the property's type, member named directly |
| `@Injected<Foo>(\.member)` | `Foo`, member named directly |
| `@Injected(seed: 1)` | the property's type, arguments forwarded into `inject(seed:)` |

## A generic argument is the key

A generic argument **is** the key, so the property may be declared as anything the resolved
value satisfies — a protocol it conforms to, a class it subclasses, or an optional wrapping
it. Compatibility is the compiler's to check: the generated accessor assigns one to the
other, so a genuine mismatch is rejected there with both real types named. It composes with
the key path — `@Injected<Serving>(\.mock)` resolves `Zerk<Serving>.mock`.

```swift
@Injectable
@Injectable<Reporting>
final class ConsoleReporter: Reporting {
    let label = "console"

    @InjectableProviding
    init() {}
}

// Resolves the *concrete* key while storing it as the protocol.
struct StatedKeyConsumer {
    @Injected<ConsoleReporter>
    var reporter: Reporting
}
```

The stated key is also what the async/throwing chain check validates, not the declared type.

## The type annotation is required

The type annotation is **required** in every form. `@Injected<Foo> var foo` cannot work:
`var foo` is `error: type annotation missing in pattern` before any macro runs, a computed
property needs an explicit type too, and no attached-macro role can rewrite the declaration
it is attached to.

## Naming a member with a key path

The key-path form picks one specific `Zerk<Key>` member rather than the primary, checked by
the compiler rather than by string matching. Because a key path can name a property but
never a method, Zerk also generates an argument-free `static var` beside every
function-shaped member whose parameters it resolves in full:

```swift
@InjectableProviding<Loading>
static func live(store: Storing) -> Loading { ... }

// generated — the method stays, the var is additional:
// static func live(store: Storing = Zerk<Storing>.inject()) -> Loading { ... }
// static var live: Loading { live() }
```

The var delegates to the method, so construction and the interjection lookup both stay in
one place.

That var is emitted only where it can exist and be reached: the member must take at least
one parameter (with none it is already a `var`), every parameter must be resolvable, the
member must be free of `async`/`throws` (Swift refuses to form a key path to such a
property), and its name must be unique for that key (two providers sharing a name are told
apart by their parameters, which an argument-free var has none of).

A key-path use is not checked against the key's primary chain, because it does not go
through the primary — and by the effect-free condition above, anything a key path can reach
is already synchronous.

Naming a member from *another* module needs
[`@Injectable(public: true)`](Injectable.md), which publicizes every generated member for
the key rather than just `inject()`. Without it those members are `internal` and a key path
cannot cross the module boundary to them.

## Optionals, and overriding what gets injected

`@Injected` requires an explicit type annotation and works with optionals (`Service?`
resolves `Service`). A value passed to the memberwise initializer still wins over the
injected default, so a caller can override what gets injected.

```swift
struct StatedKeyOptionalConsumer {
    @Injected<ConsoleReporter>
    var reporter: Reporting?
}
```

Both `Foo?`/`Foo!` and `Optional<Foo>` are unwrapped for the lookup. The property keeps its
declared type; only the key is unwrapped.

## `@InjectedDynamically`

`@Injected` resolves **once**, when the enclosing value is initialized, and keeps what it
resolved. `@InjectedDynamically` resolves on **every access**:

```swift
struct Feed {
    @Injected         var stored: SessionCache   // resolved at init, then kept
    @InjectedDynamically var live: SessionCache     // re-resolved on every read
}
```

For almost everything, `@Injected` is what you want: one lookup, no per-access cost, and a
reference that cannot change underneath the holder. `@InjectedDynamically` exists for the case
where it *should* change — a [`@Scoped`](Scoped.md) dependency held by something that
outlives the scope. `Zerk.reset(.session)` drops Zerk's reference but cannot reach one
already handed out, so a stored property goes on returning the pre-reset instance while a
dynamic one picks up the replacement.

Every `@Injected` form has a counterpart, spelled the same way:

```swift
@InjectedDynamically var service: ApiServicing
@InjectedDynamically(seed: 100) var token: SeededToken
@InjectedDynamically(\.cached) var loader: Loading
@InjectedDynamically<LiveService> var s: Serving
```

The property becomes **computed**, which is the whole mechanism and also the whole list of
differences:

- it must be a `var` — a `let` cannot be computed;
- it cannot carry `willSet`/`didSet` — there is no storage left to observe;
- it is read-only, and it does not participate in the memberwise initializer, so there is no
  "pass a value in to override it" the way there is for `@Injected`;
- resolution happens per read, so a chain that is expensive is expensive every time.

Everything else is identical. The same async/throwing chain check applies — a getter cannot
`await` any more than an initializer can — and it reports against whichever attribute you
wrote.

### Why it is a separate attribute

It would read better as an argument on `@Injected`. That does not work, and the reason is
worth recording, because the failure is nowhere near the mistake.

The two variants need different macro **roles**: `@attached(peer)` for the stored one, whose
peer initializes the property, and `@attached(accessor)` for the dynamic one, which replaces
the property's storage with a getter. **Overloads of a single macro name must agree on their
role set.** Giving `Injected` one accessor overload crashes SILGen on Swift 6.3.3 — while
expanding the *peer* variant, on ordinary `@Injected` properties that have nothing to do with
the new one. The argument's shape makes no difference: a labelled `Bool` and a positional
enum both do it.

Declaring *every* overload with both roles does stop the crash. It then forces the stored
variant to produce a non-observing accessor — an observing one is rejected outright — which
makes `@Injected` a computed property backed by its peer. That was built and measured, and
it costs behaviour documented on this page:

- with an `init` accessor, `final class C { @Injected var x: T }` stops compiling —
  *"class 'C' has no initializers"*;
- without one, the memberwise initializer can no longer override what was injected, since
  the only stored property left is private;
- either way, `@Injected let` and `willSet`/`didSet` are gone.

None of that is worth a spelling, so dynamic resolution took its own attribute name, and
every `@Injected` overload stays a peer.

## Where the declarations come from

The Zerk module declares three `Injected` macros — `Injected()`, `Injected<T>()`, and
`Injected<T>(_ keyPath:)` — and three matching `InjectedDynamically` ones. The generated file
re-declares all six inside the module it generates into, and adds one overload per distinct
`inject()` signature so arguments can be forwarded through the attribute:

```swift
@attached(peer, names: prefixed(_$zerk_injection_))
macro Injected(seed: Int) = #externalMacro(module: "ZerkMacros", type: "InjectedMacro")

@attached(accessor)
macro InjectedDynamically(seed: Int) = #externalMacro(module: "ZerkMacros", type: "InjectedDynamicallyMacro")
```

Every form has to be re-declared, including the ones that forward no arguments. Swift's name
lookup stops at the first scope that declares the name at all, so one module-local
declaration shadows *all* of that name's overloads — a form the generated file omitted would
not fall back to the library's, it would stop existing in every target the plugin runs in.
The two names shadow independently, so each carries its full set.

The library's declarations are what a target *without* the plugin uses, and they are not
redundant: a module that declares no injectables of its own can still write `@Injected var
service: ApiServicing` against an exported key from another module, or name a member of a
`Zerk<Key>` extension it declares itself. The argument-forwarding overloads cannot be generic
over the key — their labels differ per provider — so those exist only in the generated file.

## What it cannot resolve

Effects propagate through the chain: if a provider is `async`/`throws`, the generated
members and `inject()` are too, and transitive dependents inherit the effects. `@Injected`
expands to a synchronous accessor and cannot resolve such chains (the codegen emits an error
if you try); resolve them manually, or use an `@injected` parameter, whose generated
overload inherits the chain's effects.

**Manual resolution** — `Zerk<Key>.inject()` (or `try await Zerk<Key>.inject(...)` for
effectful chains) anywhere.

**Lazy resolution** — there is no `@LazyInjected` macro. Use a plain `lazy var` calling
`Zerk<Key>.inject()` directly, which is clearer and has no macro caveats:

```swift
final class Consumer {
    lazy var token: SeededToken = Zerk<SeededToken>.inject(seed: 100)
}
```

A generic key has no property spelling either — a property takes no generic parameters — so
there is no `@Injected(\.member)` key path for one. Call `Zerk<Cache<String>>.cache()` or
`inject()`. See [Generics](../Features/Generics.md).

## Shapes it rejects

The macro reports these at the declaration, before the plugin ever runs:

- more than one binding in the declaration, or a pattern that is not a plain identifier
- the `lazy` modifier
- an explicit initializer on the property — the injected expression *is* the initializer
- accessors other than `willSet`/`didSet`; a computed property has no storage to initialize
- a missing type annotation
- more than one generic argument

`@InjectedDynamically` rejects the same list, and two more: any accessor at all — including
`willSet`/`didSet`, since the property it generates is computed — and a `let` binding.

---

[← Table of contents](../TableOfContents.md)

**See also:** [Parameter markers](ParameterMarkers.md) · [`@Injectable`](Injectable.md) · [`@InjectableProviding`](InjectableProviding.md) · [`@Scoped`](Scoped.md) · [Injected examples](../Getting%20Started/InjectedExamples.md) · [Concurrency](../Features/Concurrency.md) · [Generated code](../Plugin/GeneratedCode.md) · [Interjection](../Testing/Interjection.md)
