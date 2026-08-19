# Declaring injectables — worked examples

Ten declarations, from the simplest to the awkward ones, each with the code the plugin
actually generates for it. Every block marked `// Generated:` is real `ZerkCodegen` output,
with the header trimmed — the `import` lines and the three `macro Injected` re-declarations
that open every generated file. Nothing else is abridged.

For what each attribute means, see [`@Injectable`](../Macros%20and%20Markers/Injectable.md),
[`@InjectableProviding`](../Macros%20and%20Markers/InjectableProviding.md) and
[`@InjectableValue`](../Macros%20and%20Markers/InjectableValue.md); this page is the "show me"
counterpart to those.

## A type keyed by itself

`@Injectable` with no generic argument makes the type its own key.

```swift
@Injectable
struct Clock {
    func now() -> Int { 0 }
}
```

```swift
// Generated:
extension Zerk<Clock> {
    nonisolated static var clock: Clock {
        if let interjected = _$interjected(for: \.`clock`) {
            return interjected
        }
        return Clock()
    }

    nonisolated static func inject() -> Clock {
        clock
    }

}

extension Zerk<Clock>.Interjection {
    nonisolated var `clock`: Void {}
}
```

No `@InjectableProviding` anywhere: with exactly one initializer — here the synthesized
memberwise one — Zerk infers the provider. The member is named after the type, and it gets an
[interjection point](../Testing/Interjection.md) like every other member.

## A type keyed by a protocol

The generic argument is the key. The declaration only has to be able to produce it.

```swift
@InjectableValue
var baseURL: String { "https://api.example.com" }

protocol ApiServicing: AnyObject {
    var host: String { get }
}

@Injectable<ApiServicing>
final class ApiService: ApiServicing {
    let host: String

    @InjectableProviding
    init(baseURL: String) {
        self.host = baseURL
    }
}
```

```swift
// Generated:
extension Zerk<String> {
    nonisolated static var baseURL: String {
        if let interjected = _$interjected(for: \.`baseURL`) {
            return interjected
        }
        return "https://api.example.com"
    }
}

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

extension Zerk<ApiServicing>.Interjection {
    nonisolated var `apiService`: Void {}
}
```

The `baseURL: String` parameter became a *default argument* reading the matching value, so
`inject()` still takes nothing — a caller may override it, and nothing forces them to. Because
every parameter resolved, the plugin also emits a property alongside the function, which is
what a key path like `@Injected(\.apiService)` can name.

## One type under several keys

List the keys. Each gets its own extension, and each resolves through the same provider.

```swift
protocol Reading {}
protocol Writing {}

@Injectable<Reading, Writing>
final class Store: Reading, Writing {
    @InjectableProviding
    init() {}
}
```

```swift
// Generated:
extension Zerk<Reading> {
    nonisolated static var store: Reading {
        if let interjected = _$interjected(for: \.`store`) {
            return interjected
        }
        return Store()
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
        return Store()
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

Two keys, two instances — the getter builds one per call. Add [`@Singleton`](#a-singleton) to
make both keys hand back the same object.

## Several types under one key

When more than one type claims a key, exactly one of them must say it wins.

```swift
protocol Loading {}

@Injectable<Loading>(primary: true)
final class LiveLoader: Loading {
    @InjectableProviding
    init() {}
}

@Injectable<Loading>
final class MockLoader: Loading {
    @InjectableProviding
    init() {}
}
```

```swift
// Generated:
extension Zerk<Loading> {
    nonisolated static var liveLoader: Loading {
        if let interjected = _$interjected(for: \.`liveLoader`) {
            return interjected
        }
        return LiveLoader()
    }

    nonisolated static var mockLoader: Loading {
        if let interjected = _$interjected(for: \.`mockLoader`) {
            return interjected
        }
        return MockLoader()
    }

    nonisolated static func inject() -> Loading {
        liveLoader
    }

}

extension Zerk<Loading>.Interjection {
    nonisolated var `liveLoader`: Void {}
    nonisolated var `mockLoader`: Void {}
}
```

The loser is not discarded — `Zerk<Loading>.mockLoader` is a member like any other, reachable
with `@Injected(\.mockLoader)`. Only `inject()` is contested, and leaving it so is a build
error.

## Several providers on one type

A key may have several providers, each a member of its own. Naming rides the attribute.

```swift
protocol Mailing {}

struct Mailer: Mailing {}

@Injectable<Mailing>
enum MailerProvider {
    @InjectableProviding(typeNamed: true, primary: true)
    static func live() -> Mailer { Mailer() }

    @InjectableProviding(name: "sandbox")
    static func staging() -> Mailer { Mailer() }
}
```

```swift
// Generated:
extension Zerk<Mailing> {
    nonisolated static var mailer: Mailing {
        if let interjected = _$interjected(for: \.`mailer`) {
            return interjected
        }
        return MailerProvider.live()
    }

    nonisolated static var sandbox: Mailing {
        if let interjected = _$interjected(for: \.`sandbox`) {
            return interjected
        }
        return MailerProvider.staging()
    }

    nonisolated static func inject() -> Mailing {
        mailer
    }

}

extension Zerk<Mailing>.Interjection {
    nonisolated var `mailer`: Void {}
}
```

`typeNamed: true` read the factory's **return type** — `Mailer`, not the key `Mailing` and not
the enclosing `MailerProvider`. `name:` overrode `staging` outright. Renaming moved the
interjection points with the members, and the *calls* still go to the real declarations.

## Values, a constants namespace, and opting out

A value is read from a declaration rather than built by a provider, and is matched by key
**and** name.

```swift
#ZerkImport(module: "Foundation")

@InjectableValue
var timeout: TimeInterval { 30 }

@InjectableValues(.referenced)
enum AppConstants {
    nonisolated(unsafe) static var baseURL: String = "api.example.com"
    static let retries: Int = 3

    @NonInjectable
    static let buildStamp: String = "2026-07-29"
}
```

```swift
// Generated:
extension Zerk<String> {
    nonisolated static var baseURL: String {
        get {
            if let interjected = _$interjected(for: \.`baseURL`) {
                return interjected
            }
            return AppConstants.baseURL
        }
        set {
            AppConstants.baseURL = newValue
        }
    }
}

extension Zerk<Int> {
    nonisolated static var retries: Int {
        if let interjected = _$interjected(for: \.`retries`) {
            return interjected
        }
        return AppConstants.retries
    }
}

extension Zerk<TimeInterval> {
    nonisolated static var timeout: TimeInterval {
        if let interjected = _$interjected(for: \.`timeout`) {
            return interjected
        }
        return 30
    }
}

extension Zerk<Int>.Interjection {
    nonisolated var `retries`: Void {}
}

extension Zerk<String>.Interjection {
    nonisolated var `baseURL`: Void {}
}

extension Zerk<TimeInterval>.Interjection {
    nonisolated var `timeout`: Void {}
}
```

Four things to notice. `timeout` was *copied* — its body `30` is in the generated member, which
never reads the original. The `.referenced` sweep did the opposite: `AppConstants.baseURL` is
read through on every access, and because the source is a `var`, the member is settable and
writes back. `retries` is a `let`, so it stayed read-only. `buildStamp` is absent entirely:
`@NonInjectable` took it out of the sweep. None of these emit an `inject()` — a value never
wins a key. `#ZerkImport` is there because the generated file imports `Zerk` and nothing else,
and `TimeInterval` comes from Foundation.

## A singleton

One shared instance per *type*, across every key that type claims.

```swift
protocol Reading {}
protocol Writing {}

@Singleton
@Injectable<Reading, Writing>
final class Store: Reading, Writing {
    @InjectableProviding
    init() {}
}
```

```swift
// Generated:
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

The storage is a `private enum` of its own, not a static on `Zerk<Key>` — `Zerk<Reading>` and
`Zerk<Writing>` are distinct specializations with distinct static storage, so an instance held
there would exist once *per key*. It is typed as the concrete `Store`, and both getters return
it. The interjection lookup sits in the getter rather than the storage initializer, so a double
installed later still takes effect and the real instance is never built.

## A scoped instance

One instance per named scope, dropped when that scope is reset. The same "one instance,
however many keys" arrangement as a singleton, with a different lifetime.

```swift
protocol Caching {}

extension InjectionScope {
    nonisolated static let session = InjectionScope("session")
}

@Scoped(.session)
@Injectable<Caching>
final class SessionCache: Caching {
    @InjectableProviding
    init() {}
}
```

```swift
// Generated:
// A scope named from a nonisolated slot must itself be nonisolated. Under
// SWIFT_DEFAULT_ACTOR_ISOLATION, write `nonisolated static let session = …`.
private enum _$zerk_scoped {
    nonisolated static let sessionCache = ZerkScopedBox<SessionCache>(scope: .session)
}

extension Zerk<Caching> {
    nonisolated static var sessionCache: Caching {
        if let interjected = _$interjected(for: \.`sessionCache`) {
            return interjected
        }
        return _$zerk_scoped.sessionCache.value { SessionCache() }
    }

    nonisolated static func inject() -> Caching {
        sessionCache
    }

}

extension Zerk<Caching>.Interjection {
    nonisolated var `sessionCache`: Void {}
}
```

Read it against the singleton above: same private namespace, same one-entry-per-type rule,
same guard in the getter. The difference is that the member hands the box a closure instead
of reading a stored instance — the box decides whether to run it, and the *member* is what
knows how to build. That is what keeps the box `nonisolated` for a `@MainActor` type and
`Zerk.reset(.session)` callable from anywhere.

```swift
Zerk<Caching>.inject() === Zerk<Caching>.inject()   // true
Zerk.reset(.session)
// the next inject() builds a new one
```

Everything a singleton refuses, this refuses too — caller arguments, `async`/`throws`
providers, value types, generic types, more than one provider — because the instance is built
exactly once from a synchronous expression either way. See [`@Scoped`](../Macros%20and%20Markers/Scoped.md).

## A parameter that bubbles to `inject(...)`

A provider parameter the graph cannot answer is not an error — it is exposed on the member and
on `inject(...)` for the caller to supply.

```swift
protocol Rendering {}

@InjectableValue
var baseURL: String { "https://api.example.com" }

@Injectable<Rendering>
struct Renderer: Rendering {
    @InjectableProviding
    init(baseURL: String, title: String) {}
}

struct Screen {
    @Injected(title: "Home")
    var renderer: Rendering
}
```

```swift
// Generated:
extension Zerk<String> {
    nonisolated static var baseURL: String {
        if let interjected = _$interjected(for: \.`baseURL`) {
            return interjected
        }
        return "https://api.example.com"
    }
}

extension Zerk<Rendering> {
    nonisolated static func renderer(baseURL: String = Zerk<String>.baseURL, title: String) -> Rendering {
        if let interjected = _$interjected(for: \.`renderer`) {
            return interjected
        }
        return Renderer(baseURL: baseURL, title: title)
    }

    nonisolated static func inject(title: String) -> Rendering {
        renderer(baseURL: Zerk<String>.baseURL, title: title)
    }

}

extension Zerk<Rendering>.Interjection {
    nonisolated var `renderer`: Void {}
}
```

Both parameters are `String`, and only one resolved — values are matched by key *and name*, so
`baseURL:` found the value and `title:` did not. What could not be answered became the shape of
`inject(title:)`, and the plugin adds an `@Injected(title: String)` overload to the generated
file so the attribute can forward the argument. This is what "parametric injection" means:
the unanswered parameter travels up to the consumer rather than being guessed at.

## A generic type

A generic type registers under itself, and the members bind the key per call.

```swift
@Injectable
struct Cache<E> {
    @InjectableProviding
    init(capacity: Int) {}
}

@InjectableValue
var capacity: Int { 128 }
```

```swift
// Generated:
extension Zerk<Int> {
    nonisolated static var capacity: Int {
        if let interjected = _$interjected(for: \.`capacity`) {
            return interjected
        }
        return 128
    }
}

extension Zerk {
    nonisolated static func cache<E>(capacity: Int = Zerk<Int>.capacity) -> Cache<E> where Injectable == Cache<E> {
        if let interjected = _$interjected(for: \.`cache`) {
            return interjected
        }
        return Cache(capacity: capacity)
    }

    nonisolated static func inject<E>() -> Cache<E> where Injectable == Cache<E> {
        cache()
    }

}

protocol `_$ZerkInjectable_Cache` {}
extension Cache: `_$ZerkInjectable_Cache` {}

extension Zerk<Int>.Interjection {
    nonisolated var `capacity`: Void {}
}

extension Zerk.Interjection where Injectable: `_$ZerkInjectable_Cache` {
    nonisolated var `cache`: Void {}
}
```

The extension is unconstrained `extension Zerk`, and the `where Injectable == Cache<E>` clause
on each member is what ties the key to the call — `Zerk<Cache<String>>.inject()` resolves, and
so does a dependency on any other specialization. The members are *functions*: a property takes
no generic parameters, so there is no `Zerk<Cache<String>>.cache` spelling. The marker protocol
exists because the `Interjection` extension cannot name `E` either; conforming `Cache` to it
scopes the point to the family, and an interjection still names one specialization. Generic
types cannot be `@Singleton` — its storage is a static stored property, which Swift does not
allow in a generic type.

## A type you do not declare

`@Injectable<Key>` does not require the annotated declaration to *be* `Key`. Two forms register
something from another module.

### The declaration form

`@Injectable` on a global or `static` var or func registers the type it produces, with the
declaration as its provider.

```swift
#ZerkImport(module: "Foundation")

@Injectable
var urlSession: URLSession { URLSession(configuration: .default) }
```

```swift
// Generated:
nonisolated private func _$zerk_provider_urlSession() -> URLSession { urlSession }

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

extension Zerk<URLSession>.Interjection {
    nonisolated var `urlSession`: Void {}
}
```

That is the whole registration — full membership, not a special case. The private forwarding
function is why a **global** works at all: inside `extension Zerk<URLSession>` an unqualified
`urlSession` would resolve to the member being defined and recurse. A `static` member needs no
such indirection, since `Container.session` is already unambiguous.

### The provider-type form

When several factories belong together, hang the key on a type instead.

```swift
#ZerkImport(module: "Foundation")

@Injectable
var configuration: URLSessionConfiguration { .default }

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
nonisolated private func _$zerk_provider_configuration() -> URLSessionConfiguration { configuration }

extension Zerk<URLSession> {
    nonisolated static func live(configuration: URLSessionConfiguration = Zerk<URLSessionConfiguration>.inject()) -> URLSession {
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

extension Zerk<URLSessionConfiguration> {
    nonisolated static var configuration: URLSessionConfiguration {
        if let interjected = _$interjected(for: \.`configuration`) {
            return interjected
        }
        return _$zerk_provider_configuration()
    }

    nonisolated static func inject() -> URLSessionConfiguration {
        configuration
    }

}

extension Zerk<URLSession>.Interjection {
    nonisolated var `live`: Void {}
}

extension Zerk<URLSessionConfiguration>.Interjection {
    nonisolated var `configuration`: Void {}
}
```

Both foreign registrations at once: the first form for the configuration, the second for the
session that needs it. The default argument reads `Zerk<URLSessionConfiguration>.inject()`
rather than a named member — a *type* key is resolved through `inject()`, where a *value* would
have been read by name, as `baseURL` was earlier. `URLSessionProvider` appears nowhere but as
the callee, so its name is yours to pick. Here the member is called `live`, which reads well
next to a `staging` sibling; `@InjectableProviding(typeNamed: true)` names it after the return
type instead.

You cannot point Zerk at `URLSession.init(configuration:)` directly, by a reference or a
freestanding macro or anything else. Zerk reads syntax: it would see the name but not that
`configuration` is a `URLSessionConfiguration`, so it could never emit the default that
resolves it. The one-line factory is the construct that carries the type information the graph
needs.

---

[← Table of contents](../TableOfContents.md)

**See also:** [Quick start](QuickStart.md) · [Terminology](Terminology.md) · [Consuming examples](InjectedExamples.md) · [`@Injectable`](../Macros%20and%20Markers/Injectable.md) · [`@InjectableProviding`](../Macros%20and%20Markers/InjectableProviding.md) · [`@InjectableValue`](../Macros%20and%20Markers/InjectableValue.md) · [`@Singleton`](../Macros%20and%20Markers/Singleton.md) · [Foreign types](../Features/ForeignTypes.md) · [Generics](../Features/Generics.md) · [Generated code](../Plugin/GeneratedCode.md) · [Interjection](../Testing/Interjection.md)
