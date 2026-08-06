# Consuming — worked examples

Every example here is a real fixture run through the codegen. The output is verbatim except
for the file header and the re-declared `macro Injected` overloads, which every generated
file carries and which are covered in [Generated code](../Plugin/GeneratedCode.md).

The counterpart page is [Declaring — examples](InjectableExamples.md), which covers putting
things *into* the graph.

## The graph these examples resolve against

```swift
protocol Loading { var source: String { get } }

@Injectable<Loading>(primary: true)
struct LiveLoader: Loading {
    let source = "live"

    @InjectableProviding<Loading>(primary: true)
    static func live(store: Storing) -> Loading { LiveLoader() }

    @InjectableProviding<Loading>
    static func cached() -> Loading { LiveLoader() }
}

@Injectable
struct Storing { init() {} }

@Injectable
struct SeededToken {
    let value: Int
    @InjectableProviding
    init(seed: Int) { self.value = seed }
}
```

Two providers for `Loading`, one of them primary; a plain `Storing`; and a `SeededToken`
whose provider needs an argument nothing in the graph can supply.

## 1. `@Injected`, the plain form

```swift
struct FeedViewModel {
    @Injected var loader: Loading
}
```

`@Injected` is the one Zerk macro that generates code, and what it generates is a stored
property defaulted to `Zerk<Loading>.inject()`. Nothing appears in the generated file for
it — the expansion happens at the declaration, because the expression it needs depends on
nothing but the property's own type.

The type annotation is **required** in every form. `@Injected var loader` is
`error: type annotation missing in pattern` before any macro runs, and no attached-macro
role can rewrite the declaration it is attached to.

## 2. `@Injected(\.member)` — naming a provider instead of the primary

```swift
@Injected(\.cached) var fallback: Loading
```

`inject()` gives you the primary. The key-path form picks one specific member, and because
the point is a real declaration the compiler checks it — a renamed provider is a compile
error rather than something that silently stops applying.

## 3. The companion `var`, which is what makes a key path possible

A key path can name a property but never a method. So beside every function-shaped member
whose parameters resolve in full, the plugin emits an argument-free `static var`:

```swift
extension Zerk<Loading> {
    nonisolated static func live(store: Storing = Zerk<Storing>.inject()) -> Loading {
        if let interjected = _$interjected(for: \.`live`) {
            return interjected
        }
        return LiveLoader.live(store: store)
    }

    nonisolated static var live: Loading {
        live()
    }

    nonisolated static func inject() -> Loading {
        live()
    }
}
```

The method stays; the `var` is additional. It is emitted only where it can exist and be
reached: the member must take at least one parameter (with none it is already a `var`),
every parameter must be resolvable, the member must be free of `async`/`throws` — Swift
refuses to form a key path to such a property — and its name must be unique for that key,
since two providers sharing a name are told apart by parameters an argument-free `var` does
not have.

`cached` takes no parameters, so it is already a `var` and needs no companion.

## 4. `@Injected(arg:)` — forwarding to a parametric `inject`

`SeededToken`'s provider needs a `seed: Int` that nothing in the graph supplies, so it
stays on the generated member and on `inject`:

```swift
extension Zerk<SeededToken> {
    nonisolated static func seededToken(seed: Int) -> SeededToken {
        if let interjected = _$interjected(for: \.`seededToken`) {
            return interjected
        }
        return SeededToken(seed: seed)
    }

    nonisolated static func inject(seed: Int) -> SeededToken {
        seededToken(seed: seed)
    }
}
```

The consumer supplies it through the attribute:

```swift
@Injected(seed: 100) var token: SeededToken
```

This is why the plugin re-declares `@Injected` into your module — one overload per distinct
`inject()` signature, so arguments can ride through the attribute.

## 5. `@Injected<Key>` — resolve one key, store it as another type

```swift
@Injected<LiveService> var service: Serving
```

The generic argument **is** the key; the property may be declared as anything the resolved
value satisfies — a protocol it conforms to, a class it subclasses, or an optional wrapping
it. Compatibility is the compiler's to check: the generated accessor assigns one to the
other, so a genuine mismatch is rejected there with both real types named.

It composes with the key path: `@Injected<Serving>(\.mock)` resolves `Zerk<Serving>.mock`.

## 6. Optionals

```swift
@Injected var maybeStore: Storing?
```

`Storing?` resolves `Storing`. Nothing extra is generated — the optional is just the
property's declared type.

## 7. A caller still wins over the injected default

```swift
FeedViewModel()                      // loader injected
FeedViewModel(loader: MockLoader())  // caller's value, injection skipped
```

A value passed to the memberwise initializer beats the injected default, so a consumer
remains constructible by hand.

## 8. Lazy resolution

There is no `@LazyInjected` macro. Use a plain `lazy var` calling `inject()` directly, which
is clearer and carries no macro caveats:

```swift
final class Consumer {
    lazy var token: SeededToken = Zerk<SeededToken>.inject(seed: 100)
}
```

## 9. `@injected` (lowercase) — parameter injection

Marks an initializer or method parameter; the plugin generates an overload with every
marked parameter omitted and filled via `inject()`. A class gets a `convenience init`:

```swift
final class AuditTrail {
    init(@injected foo: Foo, label: String) {}
}
```

```swift
extension AuditTrail {
    nonisolated convenience init(label: String, value: Value) {
        self.init(foo: Zerk<Foo>.inject(value: value), label: label)
    }
}
```

A struct gets a plain extension `init`:

```swift
struct Receipt {
    init(@injected payments: PaymentServicing, total: Int) {}
}
```

```swift
extension Receipt {
    nonisolated init(total: Int) {
        self.init(payments: Zerk<PaymentServicing>.inject(), total: total)
    }
}
```

Both call sites remain available — the original signature is untouched, because `@injected`
is an inert property wrapper rather than a macro. (It has to be: Swift attached macros
cannot apply to parameters.)

Notice `AuditTrail`'s overload took a `value: Value` nobody wrote. `Foo`'s own provider
needs it, so it **bubbled up** onto the generated overload. Own parameters keep their
relative order and bubbled ones are appended after them.

## 10. `@injectable` — feeding a bubbled requirement from your own parameter

When the member already declares a parameter that would satisfy a bubbled one, `@injectable`
says so, and the single parameter serves both:

```swift
final class Bar {
    init(@injected foo: Foo, @injectable value: Value) {}
}
```

```swift
extension Bar {
    nonisolated convenience init(value: Value) {
        self.init(foo: Zerk<Foo>.inject(value: value), value: value)
    }
}
```

One `value` parameter, used twice. Without the marker the same name would be declared twice
— once as `Bar`'s own, once bubbled for `Foo` — which is a build error rather than a silent
merge, so sharing is always something you wrote down. Matched by name *and* type.

## 11. `@autoinjected` — switching a provider to explicit mode

By default a provider's parameters are auto-resolved wherever Zerk can. Marking any
parameter switches that provider to explicit mode: marked parameters are resolved, unmarked
ones are always the caller's.

```swift
@Injectable
final class Checkout {
    @InjectableProviding
    init(@autoinjected payments: PaymentServicing, orderID: String) {}
}
```

```swift
nonisolated static func checkout(payments: PaymentServicing = Zerk<PaymentServicing>.inject(),
                                 orderID: String) -> Checkout {
```

`orderID` stays the caller's even if a `String` value exists in the graph.

## 12. `@noninjected` — keeping one parameter out of resolution

The inverse, for a provider that is mostly happy inferring:

```swift
@InjectableValue
var retries: Int { 3 }

@Injectable
final class RetryHolder {
    @InjectableProviding
    init(@noninjected retries: Int) {}
}
```

```swift
nonisolated static func retryHolder(retries: Int) -> RetryHolder {
```

No default, despite `Zerk<Int>.retries` existing.

## 13. Manual resolution, and effectful chains

`Zerk<Key>.inject()` works anywhere. When a provider is `async` or `throws`, the effects
propagate through every dependent, and the member splits in two:

```swift
@Injectable
struct Token {
    @InjectableProviding
    init() async throws {}
}

@Injectable
struct Client {
    @InjectableProviding
    init(token: Token) {}
}
```

```swift
extension Zerk<Client> {
    nonisolated static func client(token: Token) -> Client {
        if let interjected = _$interjected(for: \.`client`) {
            return interjected
        }
        return Client(token: token)
    }

    nonisolated static func client() async throws -> Client {
        client(token: try await Zerk<Token>.inject())
    }

    nonisolated static func inject() async throws -> Client {
        try await client()
    }
}
```

`Client`'s own provider is synchronous, but resolving its dependency is not — so the
resolving variant carries the effects and the explicit variant stays clean. Their arities
always differ, so the overload is never ambiguous, and there is still exactly one
construction point and one interjection lookup.

`@Injected` expands to a synchronous accessor and **cannot** resolve such a chain; the
codegen reports it if you try. Resolve it manually:

```swift
let client = try await Zerk<Client>.inject()
```

…or use an `@injected` parameter, whose generated overload inherits the chain's effects.
That is the one injection path supporting effectful construction.

---

[← Table of contents](../TableOfContents.md)

**See also:** [Declaring — examples](InjectableExamples.md) · [`@Injected`](../Macros%20and%20Markers/Injected.md) · [Parameter markers](../Macros%20and%20Markers/ParameterMarkers.md) · [Concurrency](../Features/Concurrency.md) · [Generated code](../Plugin/GeneratedCode.md)
