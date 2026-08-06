# `@InjectableValue`

Values are the half of the graph that is *read* rather than *built*. This page covers
`@InjectableValue` on a property and on a function, copied versus referenced values,
effectful values, the `@InjectableValues` sweep over a namespace, and
`@NonInjectable`.

## A value is not a type

**`@InjectableValue` / `@InjectableValue<Key1, Key2, …>`** — marks a *value*. On a variable
the declared type is the key and the body becomes the injected value:

```swift
@InjectableValue
var timeout: TimeInterval { 30 }
```

```swift
extension Zerk<TimeInterval> {
    nonisolated static var timeout: TimeInterval {
        if let interjected = _$interjected(for: \.`timeout`) {
            return interjected
        }
        return 30
    }
}
```

The two are separate markers because they are different things. A type is **built** by a
provider and matched by its key, so one of them wins `inject()`. A value is **read** from a
declaration and matched by key *and name* together — nothing about `inject()`, `primary:`,
or `@InjectableProviding` applies to it. Applying either marker to the other's declaration
is an error naming the replacement: `@InjectableValue` on a class, struct, enum or actor
reports *"Use `@Injectable` to register the type itself, or `@InjectableValues` to sweep up
its static properties"*, and `@Injectable(.copied)` or `@Injectable(.referenced)` reports
that the injection method applies to `@InjectableValue` only. `primary:` on a value is an
error for the same reason — a value is the sole provider for its key, so there is nothing
to be primary over.

Values participate in resolution: any provider parameter whose type matches a
uniquely-declared value is filled in automatically. A value declared inside a type must be
`static`, and values are matched by type **and name** together — which is what stops two
unrelated `String` values from being interchangeable.

```swift
@InjectableValue
var retries: Int { 3 }

@Injectable
final class Repo {
    @InjectableProviding
    init(retries: Int) {}          // resolved: Zerk<Int>.retries
}
```

Because matching demands a *unique* name, two values of one key and one name are a build
error rather than a silent choice — they would otherwise land in one `extension Zerk<Key>`
and fail as `invalid redeclaration` in a file you never wrote. The same name under
different keys is fine.

The generic form states the key spelling: `@InjectableValue<any Storing> var store: Storing`
registers `any Storing`. Each listed key must normalize to the declaration's own type —
`P` and `any P` are one key — so a value cannot claim a key it does not already declare,
unlike an `@Injectable` type that lists the protocols it conforms to.

## Copied vs. referenced values

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

```swift
extension Zerk<String> {
    nonisolated static var baseURL: String {
        get {
            if let interjected = _$interjected(for: \.`baseURL`) {
                return interjected
            }
            return Settings.baseURL
        }
        set {
            Settings.baseURL = newValue
        }
    }
}
```

A settable source produces a settable member; a `let` or a get-only computed property stays
read-only. The source must be at least `internal`, since the generated file has to see it —
a `private` value can only be copied. The default is `.copied`, and `valueInjectionMethod`
in `ZerkSettings.json` changes it globally.

A `.referenced` value declared at file scope goes through a private thunk, because a bare
`timeout` written inside `extension Zerk<Int>` would resolve to the generated member and
recurse. A member of a type is qualified as `Type.member` and needs none. See
[Generated code](../Plugin/GeneratedCode.md).

## Effectful values

A getter may be `async`, `throwing`, or both, and the resolution propagates them exactly as
an effectful provider's do:

```swift
@InjectableValue
var token: String {
    get async throws { try await keychain.token() }
}
```

```swift
extension Zerk<String> {
    nonisolated static var token: String {
        get async throws {
            if let interjected = _$interjected(for: \.`token`) {
                return interjected
            }
            return try await keychain.token()
        }
    }
}
```

A consumer that depends on it becomes effectful too. A default argument cannot `try` or
`await`, so the resolution moves into the body:

```swift
extension Zerk<Repo> {
    nonisolated static func repo(token: String) -> Repo { … }

    nonisolated static func repo() async throws -> Repo {
        repo(token: try await Zerk<String>.token)
    }

    nonisolated static func inject() async throws -> Repo {
        try await repo()
    }
}
```

An effectful value is read-only — Swift has no effectful setter — and cannot be reached by
`@Injected` or a key path, the same limits an effectful provider already carries. See
[Concurrency](../Features/Concurrency.md).

## Only a property

`@InjectableValue` does not apply to a function, and writing it on one is an error naming
the replacement:

```
@InjectableValue cannot be applied to a function. A value is read from a declaration and
matched by key and name, while a function with parameters is something the graph builds —
write '@Injectable' on it instead, which registers the type it returns with the function
as its provider. For a value that takes no arguments, use a property.
```

The distinction is the one the two markers exist to draw. A value is **read** from a
declaration and matched by key *and* name; it never wins its key's `inject()`, and
`primary:` means nothing to it. Something taking arguments is **built**, and building is
what [`@Injectable`](Injectable.md) on a global or `static` func already registers — as a
real type key, reached through `inject()` like anything else:

```swift
struct Caption { let text: String }

@Injectable(typeNamed: true)
func makeCaption(logger: Logger, label: String) -> Caption {
    Caption(text: "\(label)#\(logger.serial)")
}

Zerk<Caption>.caption(label: "x")   // `logger` resolved, `label` supplied
Zerk<Holder>.inject(label: "x")     // `label` bubbles all the way up
```

Same resolution, same bubbling, same parameter markers — the difference is that `Caption`
is a key the graph can answer for, rather than a `String` that only a parameter *named*
`caption` could ever have matched. See [Foreign types](../Features/ForeignTypes.md) for the
declaration form in full.

## `@InjectableValues` — sweeping a namespace

**`@InjectableValues`** registers every eligible static property of a type, so a constants
namespace does not need an attribute per member:

```swift
@InjectableValues(.referenced)
enum AppConstants {
    nonisolated(unsafe) static var baseURL: String = "api.example.com"
    static let retries: Int = 3

    @NonInjectable
    static let buildStamp: String = "2026-07-29"   // opted out
}
```

```swift
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
```

Functions are **not** swept: the sweep takes properties only, and passes a function over in
silence rather than reporting it — the marker is a statement about the type, not a promise
about every member. (A function in a swept namespace may still carry its own `@Injectable`,
which registers the type it returns; the sweep simply has no opinion about it.) A property
is swept up when it is `static`, at least `internal`, and
declares an explicit type — the type *is* the injection key, and a syntax-only plugin cannot
infer it, so a missing annotation is an error rather than a silent skip. `private` and
`fileprivate` members, instance properties, instance methods, and nested types are left
alone. An individual property may carry its own `@InjectableValue(...)` to override the
method, or **`@NonInjectable`** to opt out entirely.

Which members the sweep takes:

| Member | Swept |
|---|---|
| `static let`/`static var` with an explicit type, `internal` or wider | yes — computed or stored |
| Any `static func` | no — a function is not a value; skipped silently |
| `private` / `fileprivate` member | no — unreachable from the generated file |
| Instance property or instance method | no — there is no instance to read from |
| Member of a nested type | no — the sweep does not recurse |
| `static let retries = 3` (no annotation) | **error** — the annotation is the key |

Skipping is silent because marking a type is a statement about the type, not a promise that
every member qualifies. The missing annotation is the exception: it almost always means the
author expected the member to be injected.

`@InjectableValues` takes the same `ValueInjectionMethod` an individual value does, applied
to everything it sweeps, and defaults to `.default` — which defers to
`valueInjectionMethod` in [`ZerkSettings.json`](../Plugin/Settings.md). It can only be
applied to a class, struct, enum, or actor.

### `@NonInjectable`

Excludes a member from the sweep performed by `@InjectableValues`. It is only meaningful
inside a type marked `@InjectableValues`; elsewhere it does nothing, since nothing was
sweeping the member up to begin with. It contradicts `@InjectableValue` on the same
declaration, which is an error.

## Exporting values — `public:`

Zerk generates `internal` members by default, which keeps a module's graph its own business.
`public:` opts a key out of that. Unlike `primary`, it applies to values too, and
`@InjectableValues(public:)` exports a whole constants namespace at once:

```swift
@InjectableValue(public: true)
public let apiKey: String = "…"

@InjectableValues(public: true)
public enum AppConstants {
    public static let baseURL: String = "api.example.com"

    @InjectableValue(public: false)
    public static let internalTag: String = "…"   // stays internal
}
```

```swift
extension Zerk<String> {
    nonisolated public static var apiKey: String { … }
}

extension Zerk<String> {
    nonisolated public static var baseURL: String { … }
}

extension Zerk<String> {
    nonisolated static var internalTag: String { … }
}
```

Stating `public:` on a member is what overrides the sweep; a bare `@InjectableValue` says
nothing about access and inherits it.

The key type itself must be `public` — a public member cannot expose an internal type —
otherwise the request is dropped with a warning. A value's *own* declaration may stay
internal, since only the key appears in the generated member's signature and the accessor
reads the source from its body.

`public` must be written as a `true`/`false` literal — Zerk reads it from source and cannot
evaluate an expression.

Exporting a key makes its members visible, but the consuming module still has no idea the
key exists; that is what [`@ImportedInjectableValue`](ImportedInjectables.md) states on the
other side.

## Overloads

```swift
@InjectableValue
@InjectableValue<each T>
@InjectableValue(public: Bool)
@InjectableValue<each T>(public: Bool)
@InjectableValue(_ method: ValueInjectionMethod, public: Bool = false)
@InjectableValue<each T>(_ method: ValueInjectionMethod, public: Bool = false)

@InjectableValues(_ method: ValueInjectionMethod = .default, public: Bool = false)

@NonInjectable
```

`ValueInjectionMethod` is `.copied`, `.referenced`, or `.default` — the last deferring to
`valueInjectionMethod` in `ZerkSettings.json`, which is `copied` unless set otherwise. There
is no generic form of `@InjectableValues`: it names no key, it sweeps whatever its members
declare.

## Errors you can hit

| Message | Cause |
|---|---|
| `@InjectableValue registers a value. Use @Injectable to register the type itself, or @InjectableValues to sweep up its static properties.` | The attribute is on a type declaration |
| `@InjectableValue properties declared inside a type must be marked static.` | An instance property — there is no instance to read from |
| `@InjectableValue cannot be applied to a function. …` | The attribute is on a function; write `@Injectable` on it instead |
| `@InjectableValue must declare a single named binding with an explicit type.` | A tuple binding, or no type annotation |
| `'primary' applies to types only.` | `primary:` on a value |
| `'x' is private, so the generated file cannot reference it. Raise it to internal, or use .copied.` | A `.referenced` value narrower than `internal` |
| `'dup' is declared as a 'String' value more than once` | Two values of one key and name |
| `@InjectableValues needs an explicit type on 'x'` | A swept property with no type annotation |
| `@InjectableValues can only be applied to a class, struct, enum, or actor.` | The sweep on something with no members |
| `@NonInjectable contradicts @InjectableValue on the same declaration.` | Both attributes on one declaration |

See [Diagnostics](../Plugin/Diagnostics.md) for the full list.

---

[← Table of contents](../TableOfContents.md)

**See also:** [`@Injectable`](Injectable.md) · [`@InjectableProviding`](InjectableProviding.md) · [Parameter markers](ParameterMarkers.md) · [Imported injectables](ImportedInjectables.md) · [Terminology](../Getting%20Started/Terminology.md) · [Settings](../Plugin/Settings.md) · [Generated code](../Plugin/GeneratedCode.md) · [Concurrency](../Features/Concurrency.md) · [Interjection](../Testing/Interjection.md)
