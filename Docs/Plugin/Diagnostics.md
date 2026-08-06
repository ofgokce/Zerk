# Diagnostics

Every error and warning Zerk reports during a build, grouped by the area it comes from, with what triggers it and what to do about it.

All resolution errors surface at build time with source locations, pointing at your declaration rather than at generated code. Diagnostics accumulate across the whole run, so one build reports every problem instead of only the first.

Most of these are raised twice — once by the macro, against the declaration, so it shows up in the editor, and once by the build plugin, which reads the same source independently. The wording is shared between the two so the two reports of one mistake read the same.

## Providers and primaries

| What triggers it | The fix |
|---|---|
| `@Injectable<Key>` on a type with no `@InjectableProviding` member and no initializer to adopt | Mark an initializer or a static factory with `@InjectableProviding` |
| Several types are injectable under one key and none is primary | `@Injectable(primary: true)` on the one that should back `inject()` |
| Several types are marked primary for one key | Only one type can be primary for a key — drop the others |
| The winning type declares several providers for a key and none is primary | `@InjectableProviding(primary: true)` on one of them |
| The winning type declares several primary providers for a key | Only one provider can be primary for a key |
| `@InjectableProviding<Key>` on a member of a type that has no matching `@Injectable<Key>` | Add the key to the type, or drop it from the provider |
| A dependency cycle | The error names the cycle path (`A -> B -> A`); break it by removing one edge — inject a factory, or make one edge parametric |

## Singletons

| What triggers it | The fix |
|---|---|
| `@Singleton` on a struct or enum | Reference types only (`class` or `actor`) |
| A singleton's provider is `async` or `throws` | Singleton storage is initialized synchronously — drop the effects, or drop `@Singleton` |
| A singleton's provider takes external arguments | A singleton is built once, so there is no call site to supply them |
| A singleton depends on something in a different isolation domain | Resolving it would need `await`. Make the dependency share the singleton's isolation, or drop `@Singleton` and resolve through `inject()` |
| A singleton declares more than one provider for one key | A singleton has exactly one provider in total — the same one for every key it claims — keep whichever builds the shared instance |
| A singleton resolves to different providers for different keys | One instance means one provider across all its keys |
| A multi-key singleton whose provider returns a key rather than the concrete type | The provider must return the concrete type — storage typed as one key cannot serve the others |
| Two singleton types would store under the same generated member name | Rename one of the types |

A singleton that crosses an isolation boundary is checked for `Sendable` — see [The one diagnostic that is not Zerk's](#the-one-diagnostic-that-is-not-zerks).

## Values

| What triggers it | The fix |
|---|---|
| Two values share a key *and* a name | Values are matched by name as well as type, so two of one name under one key can never be told apart. Rename one, or register it under a different key |
| A value's generated member collides with a provider's | Rename the `@InjectableValue`, or register it under a different key |
| `@InjectableValue` on a binding that is not a single named binding with an explicit type | The type is the key, and Zerk reads syntax, so it cannot infer one |
| An `@InjectableValues` sweep picks up a member with no explicit type | Annotate it, or move the member out of the marked type |
| A `.copied` value with no body | The body is what produces the value |
| `primary:` on a value | A value is the sole provider for its key, so there is nothing to be primary over |
| A positional injection method (`.copied`/`.referenced`) on `@Injectable` | It applies to values only — a type is built by a provider, not read from a declaration |

## Imports

| What triggers it | The fix |
|---|---|
| A key is both imported and declared `@Injectable` in this module | Remove the import, or the local declaration |
| One key imported more than once | Keep the one you meant — the error names the other location |
| An `@ImportedInjectable` body that is not a single `Zerk` expression | Zerk inlines it wherever the dependency is resolved, so it cannot contain other logic — write `Zerk<Key>.staging` and nothing else |
| `@ImportedInjectable` on something other than a function, or with no return type | The return type is the key it imports |
| An imported value colliding with a local one of the same name | Rename the import, or drop the local declaration |
| The same value name imported twice | Values are matched by name, so rename one of them |
| `@ImportedInjectableValue` written as an assignment rather than a getter | It reads the other module's value on every resolution, so it needs a getter: `static var apiKey: String { Zerk<String>.apiKey }` |
| An `@ImportedInjectableValue` getter that is not a single `Zerk` expression | Same reason as `@ImportedInjectable` — it is inlined, so it cannot contain other logic |
| `@ImportedInjectableValue` with no member named, or with no explicit type | Name the member; there is no primary value for a key to fall back on |
| `#ZerkImport` with no module names | `#ZerkImport(module: "Foundation")` — at least one |
| `#ZerkImport` given anything but plain string literals | Zerk reads these from source and cannot evaluate an expression |

## Key aliases

| What triggers it | The fix |
|---|---|
| `@ZerkAlias` on something that is not a `typealias` | It relates two spellings of one key; only a typealias states that |
| `@ZerkAlias` on a generic typealias | Zerk matches keys by spelling rather than resolving them — alias a concrete instantiation instead |
| `#ZerkAlias` with fewer than two distinct types | It needs at least two types to relate, written `#ZerkAlias<A, B>()` — every listed type must be a distinct key |

## Parameter markers

| What triggers it | The fix |
|---|---|
| An `@autoinjected` parameter whose type is not injectable in this module | Declare it `@Injectable`, or drop `@autoinjected` and pass it in |
| `@autoinjected` on a declaration that is not the type's provider — **warning** | Mark it `@InjectableProviding`, or move the marked parameters to the provider. Inert rather than wrong, but a mark being ignored is exactly what marking was written to rule out |
| A bubbled requirement colliding with an unmarked parameter of the same name | Resolving the dependency needs a parameter the member already declares under that name. Mark it `@injectable` to feed the same value to both |
| One parameter marked both `@autoinjected` and `@noninjected` | Keep the one you meant |
| An `@injected` parameter whose type is not injectable in this module | Declare it `@Injectable`, or remove `@injected` |
| `@injected` on a parameter with a default value, a variadic, or an `inout` | None of the three can carry a generated default |
| `@injected` or `@autoinjected` on a property | Those are parameter markers — use `@Injected` for properties |
| Two `@injected` members of one type generating the same overload | Differentiate the remaining parameters |

## Generics

| What triggers it | The fix |
|---|---|
| A generic parameter the key erased and no argument recovers | Accept it as a parameter, or drop the key so the type registers under itself |
| A generic parameter the provider declares that nothing in its signature mentions | Take it as a parameter, or drop it from the declaration |
| A generic `@InjectableProviding` factory | Not emittable — the generated member cannot be spelled |
| A generic `@InjectableValue` function | The key is the return type, and Zerk reads syntax so it cannot substitute a type parameter |
| `@Singleton` on a generic type | Permanent: a singleton lives in a static stored property, which Swift does not allow in a generic type |
| `@Injectable(parameterized: true)` on a type with no generic parameters | Drop the argument |
| `@Injectable(parameterized: true)` with a key that is not written as an existential | Write `any P` — a parameterized protocol type is only spelled with `any`, and Zerk never adds it |
| `parameterized: true` where the type's parameter count and the protocol's primary associated types disagree | They must match, or the key cannot be spelled |
| `@injected` on a generic type or generic member | Not supported |

## Isolation and concurrency

| What triggers it | The fix |
|---|---|
| `@Isolated<A>` on a declaration also marked `nonisolated` | They contradict; Zerk cannot guess which is right |
| `@Isolated<A>` on a declaration also carrying a different global-actor attribute | Same — remove one |
| `@Isolated` on an `actor` | An actor constructs nonisolated (SE-0327). Remove the annotation; actor isolation applies to the actor's methods, not to building it |
| `@Isolated` with no type argument, or more than one | Exactly one global actor type: `@Isolated<MainActor>` |
| Under Swift 5 language mode without an SE-0411 opt-in, an isolated provider resolving a same-domain isolated dependency | Set `SWIFT_UPCOMING_FEATURE_ISOLATED_DEFAULT_VALUES=YES` and `"isolatedDefaultValues": true`, or `SWIFT_STRICT_CONCURRENCY=complete` and `"strictConcurrency": "complete"` — or mark the providers `nonisolated` |
| `@Injected` on a key with an async, throwing, or cross-isolation dependency chain | Resolve manually with `try await Zerk<Key>.inject()` |

The Swift 5 diagnostic names the three settings it read out of `ZerkSettings.json`, so a mismatch between the file and the target's build settings is visible in the message itself. See [Settings](Settings.md).

## Member names and naming arguments

| What triggers it | The fix |
|---|---|
| Two generated members with the same name *and* the same parameters under one key | Rename the type, or give the provider a distinct `@InjectableProviding` function name |
| `typeNamed:` given anything but a `true`/`false` literal | Zerk reads this from source and cannot evaluate an expression |
| `name:` given anything but a string literal — interpolation counts | Same; `"\(prefix)Session"` has segments Zerk cannot resolve |
| `typeNamed: true` and `name:` on one attribute | They name the same member two ways — keep one |
| `@InjectableProviding(typeNamed:)` on an initializer | An initializer can only produce its own type, so its member is named after that already. Write `name:` to call it something else |
| `typeNamed:` on a factory whose return type has no name to lend (`[String]`, a tuple, a function type) | Only a named type can lend one — write `name:` instead |

## Declaration form and access

| What triggers it | The fix |
|---|---|
| `@Injectable` on an `extension` | Refused: an extension states no generic parameters and has no initializer to adopt. Put the key on a provider type instead — `@Injectable<URLSession> enum URLSessionProvider { @InjectableProviding static func live() -> URLSession { … } }` |
| `@Injectable(public: true)` on a key that is not itself public — **warning** | The generated member cannot be public either; raise the key's access or drop the argument |
| `@Injectable` on an instance member | The generated file calls the member directly, and an instance member has no such reference — make it `static` |
| `@Injectable` on a `private` or `fileprivate` declaration | The generated file is a separate file in this module; raise it to at least `internal` |
| A `.referenced` value that is `private` or `fileprivate` | Raise it to `internal`, or use `.copied` |
| An `@injected` member that is `private` or `fileprivate` | The generated overload lives in a separate file and cannot call it |
| `@Injectable(primary:)` or `(public:)` given anything but a `true`/`false` literal | Zerk reads this from source and cannot evaluate an expression |
| `@InjectableProviding` on something other than an initializer or a `static` function, or on a function with no return type | The return type is the key |

## The one diagnostic that is not Zerk's

One diagnostic comes from the compiler rather than Zerk: a non-`Sendable` `@Singleton` injected across an isolation boundary. Zerk emits a `Sendable` constraint check with an explanatory comment so the failure lands somewhere legible instead of inside a factory body.

The check is emitted unconditionally wherever a singleton crosses a boundary — it costs nothing when the type already conforms. For a `@MainActor @Singleton final class Logger` resolved by a nonisolated `Reporter`, the generated file carries:

```swift
private func _$zerk_sendable_conformance_check<T: Sendable>(_: T.Type) {}

private func _$zerk_sendable_conformance_check_Logger_in_Reporter() {
    // '@Singleton Logger' is injected into 'Reporter'.
    // Singletons that cross isolation domains must be Sendable.
    _$zerk_sendable_conformance_check(Logger.self)
}
```

When the consumer is itself isolated, the comment names its domain — `is injected into 'MainActor'-isolated 'Dashboard'`.

Zerk cannot prove `Sendable` from syntax, and does not try; the compiler decides, and the failure lands on a line carrying the explanation.

---

[← Table of contents](../TableOfContents.md)

**See also:** [Limitations](Limitations.md) · [How it works](HowItWorks.md) · [Settings](Settings.md) · [Generated code](GeneratedCode.md) · [Concurrency](../Features/Concurrency.md) · [Generics](../Features/Generics.md) · [`@Singleton`](../Macros%20and%20Markers/Singleton.md) · [Parameter markers](../Macros%20and%20Markers/ParameterMarkers.md) · [Imported injectables](../Macros%20and%20Markers/ImportedInjectables.md)
