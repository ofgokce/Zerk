# @InjectableProviding

`@InjectableProviding` marks a way to build an [`@Injectable`](Injectable.md) type. This page covers where it may be written, how it binds to a key, how several providers coexist under one key, the two arguments that name the member it generates, and the order in which its parameters are resolved.

## Marking a provider

**`@InjectableProviding`** — marks a way to build the type. Place on an initializer or a `static` factory function. `@InjectableProviding<Key>` binds a provider to one specific key when a type is injectable under several; a bare `@InjectableProviding` serves every key the type claims. The two **combine** rather than shadowing each other, so a key can be served by both at once.

```swift
@Injectable<UserService>
final class LiveUserService: UserService {
    @InjectableProviding<UserService>
    static func live(apiService: ApiServicing, logger: Logger) -> UserService { ... }
}
```

The macro is semantically inert: it validates, then returns the declaration's own statements unchanged, so the body you wrote is the body that runs. The build plugin reads the marked declaration's signature to work out what the type depends on.

### The declarations it accepts

A provider must be callable without an instance and must return one. Each of these is refused, at the declaration, by the macro itself:

| written | refused with |
|---|---|
| a non-`static` function | `@InjectableProviding on a function requires the function to be static.` |
| a function returning `Void` or `()` | `@InjectableProviding functions must return a value.` |
| a function with no return clause | `@InjectableProviding functions must declare a return type.` |
| anything that is neither an initializer nor a function | `@InjectableProviding can only be applied to an initializer or a static function.` |
| `@InjectableProviding<Key>` on an initializer | `@InjectableProviding with a generic argument is not supported on initializers.` |

The last one is the same rule stated from the other side: an initializer can only ever produce its own type, so the key is whatever `@Injectable` claims and there is nothing for a written key to decide.

### The overloads

These are the public declarations, in `Sources/Zerk/Macros/InjectableProviding.swift`. There are no others.

```swift
@InjectableProviding
@InjectableProviding<each T>
@InjectableProviding(primary: Bool)
@InjectableProviding<each T>(primary: Bool)
@InjectableProviding(typeNamed: Bool, primary: Bool = false)
@InjectableProviding<each T>(typeNamed: Bool, primary: Bool = false)
@InjectableProviding(name: String, primary: Bool = false)
@InjectableProviding<each T>(name: String, primary: Bool = false)
```

The generic parameter is a pack, so one attribute can name several keys: `@InjectableProviding<Loading, Caching>` binds the provider to both and generates a member under each.

### Typed and untyped attributes union

A key's providers are the union of the `@InjectableProviding<Key>` declarations naming it and the untyped `@InjectableProviding` declarations, which serve every key on their type. Neither hides the other:

```swift
@Injectable<Loading>
@Injectable<Caching>
struct Store: Loading, Caching {
    @InjectableProviding
    static func shared() -> Store { .init() }

    @InjectableProviding<Loading>(primary: true)
    static func live() -> Store { .init() }
}
```

`Zerk<Loading>` gets both `live` and `shared`; `Zerk<Caching>` gets `shared` alone, and it wins that key uncontested.

## Inferred providers

If no provider is marked at all, Zerk infers one from a single initializer, including synthesized memberwise (structs) and default initializers. Marking any provider suppresses that inference — declaring one is a deliberate choice, and a bare initializer must not silently join it. A type with multiple initializers and no marked provider is an error:

```
No @InjectableProviding provider found for @Injectable<Loading> on 'Loader'.
```

## Several providers per key

A key may have **several** providers, each generated as its own named member. When it does, the one `inject()` should call is marked `primary`:

```swift
@Injectable<Loading>
final class Loader: Loading {
    @InjectableProviding<Loading>(primary: true)
    static func live() -> Loading { ... }

    @InjectableProviding<Loading>
    static func cached() -> Loading { ... }
}

Zerk<Loading>.live       // both members exist
Zerk<Loading>.cached
Zerk<Loading>.inject()   // live, because it is primary
```

That fixture generates, verbatim:

```swift
extension Zerk<Loading> {
    nonisolated static var cached: Loading {
        if let interjected = _$interjected(for: \.`cached`) {
            return interjected
        }
        return Loader.cached()
    }

    nonisolated static var live: Loading {
        if let interjected = _$interjected(for: \.`live`) {
            return interjected
        }
        return Loader.live()
    }

    nonisolated static func inject() -> Loading {
        live
    }
}
```

`primary` must be a `true`/`false` literal — Zerk reads it from source and cannot evaluate an expression. It is only *required* of the type that wins the key (see [`@Injectable(primary:)`](Injectable.md)); writing it on a lone provider is accepted and has no effect.

Providers that share a member name are fine as long as their parameters differ — two marked initializers are both named after their type, and the generated overloads are told apart exactly as the initializers are.

## Naming the member

**Naming the member.** A factory's member takes the factory's name and an initializer's takes its type's, which is right while the provider lives with the thing it builds. It stops being right for a provider *type*, whose whole purpose is to build something it is not — `MailerProvider.live` describes neither the key nor what comes back. Two arguments move it:

| written | member |
|---|---|
| `@InjectableProviding static func live() -> Mailer` | `live` |
| `@InjectableProviding(typeNamed: true) static func live() -> Mailer` | `mailer` |
| `@InjectableProviding(name: "sandbox") static func staging() -> Mailer` | `sandbox` |
| `@InjectableProviding init()` on `struct NullMailer` | `nullMailer` |
| `@InjectableProviding(name: "silent") init()` on `struct NullMailer` | `silent` |

`typeNamed:` reads the **return type** — not the enclosing type, and not the key, so `@InjectableProviding<Mailing>(typeNamed: true) static func live() -> Mailer` gives `Zerk<Mailing>.mailer`. It is a factory-only argument: an initializer can only ever produce its own type, so its member carries that name already and writing `typeNamed:` there is an error naming `name:` as the fix. `name:` takes a string literal; Zerk reads syntax and cannot evaluate an expression or an interpolation. Stating both is an error.

A nested return type lends only its last component: a factory returning `Keychain.Store` gives `Zerk<Keychain.Store>.store`, because `keychain.Store` is not an identifier.

### Naming is per attribute

Naming rides the attribute, exactly as `primary` does, so one factory bound to two keys can be called something different under each:

```swift
@InjectableProviding<Loading>(name: "live")
@InjectableProviding<Caching>(typeNamed: true)
static func make() -> Store { ... }

Zerk<Loading>.live
Zerk<Caching>.store
```

## The name is what you call it by, not what gets called

These are two different names, and only one of them moves.

The **callee** is the declaration Zerk emits a call to — `MailerProvider.live()`, `Loader()`, `Store.make()`. It is fixed by the source: it is the factory's own name, or the type's for an initializer, and no argument on `@InjectableProviding` changes it.

The **member name** is what the call site says — `Zerk<Mailing>.mailer`. `typeNamed:` and `name:` move only this one.

Renaming moves the interjection point with it, and the *call* still goes to the real declaration — `Zerk<Mailing>.mailer` returns `MailerProvider.live()`. From this input:

```swift
protocol Mailing {}
struct Mailer: Mailing {}

@Injectable<Mailing>
enum MailerProvider {
    @InjectableProviding<Mailing>(typeNamed: true)
    static func live() -> Mailer { .init() }
}
```

Zerk generates:

```swift
extension Zerk<Mailing> {
    nonisolated static var mailer: Mailing {
        if let interjected = _$interjected(for: \.`mailer`) {
            return interjected
        }
        return MailerProvider.live()
    }

    nonisolated static func inject() -> Mailing {
        mailer
    }
}

extension Zerk<Mailing>.Interjection {
    var `mailer`: Void {}
}
```

Three names in three places, and the rename reached exactly two of them. The member is `mailer`. The [interjection point](../Testing/Interjection.md) is `\.mailer`, so a test overrides it under the name the call site uses, not the one the factory was declared with. The body still reads `MailerProvider.live()` — the factory is called by its real name, because that is the only name Swift knows it by.

The same holds when `inject()` is involved. A provider written `@InjectableProviding(name: "live", primary: true) static func make() -> Loading` generates `static var live`, `inject()` returns `live`, and the body of `live` reads `return Loader.make()`.

Diagnostics follow the same split: a refusal names the declaration it is complaining about, never the member the rename would have produced. A generic factory written `@InjectableProviding(name: "live") static func make<E>() -> Store<E>` is reported against `'make'`, since `live` appears nowhere in the source being read.

## Refusals

Each is raised twice: by the macro, against the declaration, so it shows up in the editor, and again by the build plugin, which reads the same source independently.

| written | refused with |
|---|---|
| `typeNamed:` on an initializer | `@InjectableProviding(typeNamed:) does not apply to an initializer: it can only produce its own type, so its member is named after that type already. Write 'name:' to call it something else.` |
| `typeNamed:` on a factory returning an unnamed type — `(Int, String)`, `[String]`, a function type | `@InjectableProviding(typeNamed:) takes the member's name from the type produced, and '(Int, String)' has none to lend — it is not a named type. Write 'name:' instead.` |
| both arguments at once | `@InjectableProviding states both 'typeNamed: true' and 'name: "sandbox"'. They name the same member two ways — keep one.` |
| `name:` given anything but a string literal, interpolation included | `@InjectableProviding(name:) requires a string literal. Zerk reads this from source and cannot evaluate an expression or an interpolation.` |
| `typeNamed:` given anything but a literal | `@InjectableProviding(typeNamed:) requires a 'true' or 'false' literal. Zerk reads this from source and cannot evaluate an expression.` |
| `primary:` given anything but a literal | `@InjectableProviding(primary:) requires a 'true' or 'false' literal. Zerk reads this from source and cannot evaluate an expression.` |

A rename that collides with a sibling is reported too. Two factories told apart by their own names are not told apart once both are named after what they return:

```swift
@Injectable<Session>
enum SessionProvider {
    @InjectableProviding(typeNamed: true, primary: true)
    static func live() -> Session { .init() }

    @InjectableProviding(typeNamed: true)      // collides with the member above
    static func mock() -> Session { .init() }
}
```

## Parameter resolution

Provider parameters are resolved in this order: a uniquely matching [`@InjectableValue`](InjectableValue.md) → a uniquely resolvable injectable key (recursively) → otherwise the parameter is exposed on the generated member and on `inject(...)` for the caller to supply ("parametric injection").

All three appear at once here:

```swift
@InjectableValue
let baseURL: String = "api.example.com"

@Injectable<Logging>
struct Logger: Logging {
    init() {}
}

@Injectable<UserServicing>
struct LiveUserService: UserServicing {
    @InjectableProviding<UserServicing>
    static func live(baseURL: String, logger: Logging, userID: Int) -> UserServicing { ... }
}
```

`baseURL` matches the value, `logger` resolves to a key, and `userID` is neither, so it survives onto the signature:

```swift
extension Zerk<UserServicing> {
    nonisolated static func live(baseURL: String = Zerk<String>.baseURL, logger: Logging = Zerk<Logging>.inject(), userID: Int) -> UserServicing {
        if let interjected = _$interjected(for: \.`live`) {
            return interjected
        }
        return LiveUserService.live(baseURL: baseURL, logger: logger, userID: userID)
    }

    nonisolated static func inject(userID: Int) -> UserServicing {
        live(baseURL: Zerk<String>.baseURL, logger: Zerk<Logging>.inject(), userID: userID)
    }
}
```

The resolved parameters become defaulted, so they can still be overridden at the call site; the unresolved one has no default and must be supplied.

---

[← Table of contents](../TableOfContents.md)

**See also:** [Injectable](Injectable.md) · [InjectableValue](InjectableValue.md) · [Singleton](Singleton.md) · [Foreign types](../Features/ForeignTypes.md) · [Generated code](../Plugin/GeneratedCode.md) · [Diagnostics](../Plugin/Diagnostics.md) · [Interjection](../Testing/Interjection.md)
