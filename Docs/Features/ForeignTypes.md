# Registering a type you do not declare

Two forms put a key somewhere other than the type that carries it: on a global or static declaration that produces the type, or on a provider type that builds it. This page covers both, where each may go, and why the alternatives you might reach for first are refused.

`@Injectable<Key>` does not require the annotated declaration to *be* `Key`. The declaration is only where the providers live; the key is what they build. That is how a type from another module — `URLSession`, a vendor SDK's client, anything you cannot annotate — joins the graph:

```swift
@Injectable
var urlSession: URLSession { URLSession(configuration: .default) }
```

That is the whole registration. `@Injectable` on a **global or static** var or func registers the type it *produces*, with the declaration as its provider:

```swift
// Generated:
extension Zerk<URLSession> {
    nonisolated static var urlSession: URLSession {
        if let interjected = _$interjected(for: \.`urlSession`) {
            return interjected
        }
        return _$zerk_provider_urlSession()
    }

    nonisolated static func inject() -> URLSession {
        urlSession
    }
}
```

Full membership, not a special case: anything asking for a `URLSession` resolves through `inject()`, and the member gets an interjection point like any other.

## Naming the member

The member takes the declaration's own name. Two arguments change that, and they are alternatives — stating both is an error:

| written | key | member |
|---|---|---|
| `@Injectable var urlSession: URLSession` | `URLSession` | `urlSession` |
| `@Injectable<URLSessionProtocol> var urlSession: URLSession` | `URLSessionProtocol` | `urlSession` |
| `@Injectable(typeNamed: true) var dummyName: URLSession` | `URLSession` | `urlSession` |
| `@Injectable(name: "mainSession") var dummyName: URLSession` | `URLSession` | `mainSession` |
| `@Injectable<URLSessionProtocol>(typeNamed: true) var dummyName: URLSession` | `URLSessionProtocol` | `urlSession` |

`typeNamed:` reads the **produced type**, not the key — the last row is named from `URLSession`, not from `URLSessionProtocol`. `name:` takes a string literal; Zerk reads syntax and cannot evaluate an expression or an interpolation.

An acronym that begins the name is lowercased whole, per the Swift API Design Guidelines: `URLSession` gives `urlSession`, `APIService` gives `apiService`, `UTF8Decoder` gives `utf8Decoder`. The same rule names every member Zerk derives from a type — see [Member naming](../Getting%20Started/Terminology.md#member-naming).

## Functions, including generic ones

A function's parameters are dependencies like any provider's, and a generic function registers exactly as a generic type does:

```swift
@Injectable
func makeClient(config: Config) -> Client { … }
// static func makeClient(config: Config = Zerk<Config>.config) -> Client

@Injectable(typeNamed: true)
func makeBox<X, Y>(x: X, y: Y) -> Box<X, Y> { … }
// static func box<X, Y>(x: X, y: Y) -> Box<X, Y> where Injectable == Box<X, Y>
```

The generic form lands in an unconstrained `extension Zerk` that binds the key per call, so `Zerk<Box<Int, String>>.box(x: 1, y: "a")` resolves — see [Generics](Generics.md) for what that entails.

## Where it may go

Global, or `static` on a type. An instance member is refused — the generated file calls the declaration directly and has no instance to call it on — and so is anything below `internal`, since that file cannot see it. A **global** is reached through a generated private forwarding function rather than by name: inside `extension Zerk<Key>` an unqualified `urlSession` resolves to the member being defined, so reading it directly would recurse. A static member needs none; `Container.session` is already unambiguous.

```swift
// Generated alongside the extension, for a global:
private func _$zerk_provider_urlSession() -> URLSession { urlSession }
```

The thunk carries a function's parameters through as well — `private func _$zerk_provider_makeBox<X, Y>(x: X, y: Y) -> Box<X, Y> { makeBox(x: x, y: y) }`.

## Or put the key on a provider type

When several factories belong together, the key can go on a type instead. The declaration carrying `@Injectable<Key>` does not have to *be* `Key`:

```swift
@Injectable<URLSession>
enum URLSessionProvider {
    @InjectableProviding
    static func live(configuration: URLSessionConfiguration) -> URLSession {
        URLSession(configuration: configuration)
    }
}
```

```swift
// Generated:
extension Zerk<URLSession> {
    nonisolated static func live(configuration: URLSessionConfiguration = Zerk<URLSessionConfiguration>.configuration) -> URLSession {
        if let interjected = _$interjected(for: \.`live`) {
            return interjected
        }
        return URLSessionProvider.live(configuration: configuration)
    }

    nonisolated static var live: URLSession {
        live()
    }

    nonisolated static func inject() -> URLSession {
        live()
    }
}
```

Every parameter defaults from the graph here, so the func earns a no-argument `var` beside it and `Zerk<URLSession>.live` reads as a property; a factory with a parameter the caller must pass gets only the func.

The provider's own `configuration` dependency resolves from the graph, and `URLSessionProvider` appears nowhere except as the callee — pick any name you like, or hang several unrelated keys off separate provider types.

Here `live` is the member's name too, which reads well next to a `staging` sibling and less well on its own. `@InjectableProviding` takes the same two naming arguments as `@Injectable` does, so `@InjectableProviding(typeNamed: true)` names the member from the factory's return type rather than from a declared one — the same spelling the declaration form produces. See [@InjectableProviding](../Macros%20and%20Markers/InjectableProviding.md).

### The wrapper is required, and it is not a workaround

You cannot point Zerk at `URLSession.init(configuration:)` directly — by a reference, a freestanding macro, or anything else. Zerk reads syntax: it would see the name but not that `configuration` is a `URLSessionConfiguration`, so it could never emit the default that resolves it. The one-line factory is the construct that carries the type information the graph needs, and it is where you would put the wiring anyway.

### `@Injectable` on an `extension` is refused

The diagnostic points at the form above. An extension is not a declaration — it states no generic parameters of its own, so `extension Wrapper` cannot say whether `Wrapper` is generic, and for a foreign type there is no way to find out. It also has no initializer to adopt implicitly, and a `where` clause would make its providers conditional on something the key cannot express.

An `@InjectableValue` written inside an extension is still collected; only `@Injectable` on the extension itself is refused.

### This is not `@InjectableValue`

A value is matched by key *and name*, and produces no `inject()`; a provider type registers a real type key. Use [`@InjectableValue`](../Macros%20and%20Markers/InjectableValue.md) for configuration the graph reads, and a provider type for a dependency the graph builds.

---

[← Table of contents](../TableOfContents.md)

**See also:** [@Injectable](../Macros%20and%20Markers/Injectable.md) · [@InjectableProviding](../Macros%20and%20Markers/InjectableProviding.md) · [@InjectableValue](../Macros%20and%20Markers/InjectableValue.md) · [Imported injectables](../Macros%20and%20Markers/ImportedInjectables.md) · [Generics](Generics.md) · [Interjection](../Testing/Interjection.md)
