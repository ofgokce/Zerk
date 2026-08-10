# Generic injectables

How a generic type reaches the graph: the three keys it can register under, what
the plugin emits for each, and how a generic key stays interjectable per
specialization.

## Three registration modes

A generic type can be registered three ways, and which one you get depends on the key you write. They are genuinely different — the same attribute with and without `parameterized:` means opposite things — so the table is worth reading before the prose:

| you write | key | resolved as |
|---|---|---|
| `@Injectable` | the type itself | `Zerk<Cache<String>>.inject()` |
| `@Injectable<any P>` | `any P`, parameters erased | `Zerk<any P>.inject(1, "a")` |
| `@Injectable<any P>(parameterized: true)` | `any P<X, Y>` | `Zerk<any P<Int, String>>.inject(1, "a")` |

## The type's own key

**Generic types register under themselves, and only under themselves.** `@Injectable struct Cache<E>` becomes members of an unconstrained `extension Zerk` that bind the key per call — `static func cache<E>() -> Cache<E> where Injectable == Cache<E>` — so `Zerk<Cache<String>>.inject()` resolves, and a dependency on any specialization resolves with it. A concrete registration for one specialization coexists with the generic one and wins it, exactly as Swift's own overload resolution does. Three limits:

- **No `@Singleton`.** Its storage is a static stored property, which Swift does not allow in a generic type — there is nowhere to keep one instance per specialization. This one is permanent.
- **`@InjectableValue` on a generic function** stays refused: a value's key *is* its return type, so a free parameter there is a key nothing can register.
- **Members are functions.** A property takes no generic parameters, so a generic key has no `Zerk<Cache<String>>.cache` spelling and no `@Injected(\.member)` key path — call `Zerk<Cache<String>>.cache()` or `inject()`.

From

```swift
@Injectable
struct Cache<E> {
    @InjectableProviding
    init() {}
}
```

the plugin emits, verbatim:

```swift
extension Zerk {
    nonisolated static func cache<E>() -> Cache<E> where Injectable == Cache<E> {
        if let interjected = _$interjected(for: \.`cache`) {
            return interjected
        }
        return Cache()
    }

    nonisolated static func inject<E>() -> Cache<E> where Injectable == Cache<E> {
        cache()
    }

}

protocol `_$ZerkInjectable_Cache` {}
extension Cache: `_$ZerkInjectable_Cache` {}

extension Zerk.Interjection where Injectable: `_$ZerkInjectable_Cache` {
    nonisolated var `cache`: Void {}
}
```

The extension header cannot bind the key — `extension Zerk<Cache<E>>` has no `E` to name — so each member binds it itself with a `where` clause.

## A concrete key, erasing the parameters

**A generic type may also register under a concrete key, erasing its parameters.** The attribute cannot name them — `@Injectable<Cache<E>>` is rejected by Swift itself — but a key that erases them works, provided every parameter arrives as an argument the caller can supply:

```swift
@Injectable<any Boxable>
struct Box<X, Y>: Boxable {
    @InjectableProviding init(_ x: X, _ y: Y) { … }
}

// extension Zerk<any Boxable> {
//     static func box<X, Y>(_ x: X, _ y: Y) -> any Boxable { … }
//     static func inject<X, Y>(_ x: X, _ y: Y) -> any Boxable { box(x, y) }
// }

@Injected(1, "a") var box: any Boxable
```

The real emission, for `protocol Boxable { associatedtype X; associatedtype Y }`:

```swift
@attached(peer, names: prefixed(_$zerk_injection_))
macro Injected<X, Y>(_: X, _: Y) = #externalMacro(module: "ZerkMacros", type: "InjectedMacro")

extension Zerk<any Boxable> {
    nonisolated static func box<X, Y>(_ x: X, _ y: Y) -> any Boxable {
        if let interjected = _$interjected(for: \.`box`) {
            return interjected
        }
        return Box(x, y)
    }

    nonisolated static func inject<X, Y>(_ x: X, _ y: Y) -> any Boxable {
        box(x, y)
    }

}

extension Zerk<any Boxable>.Interjection {
    nonisolated var `box`: Void {}
}
```

No `where` clause: the header already bound the key. The `@Injected` overload that takes `(1, "a")` is generated alongside it.

## A provider with generic parameters of its own

**A provider may add generic parameters of its own**, on a generic type or a plain one:

```swift
@Injectable
struct Box { init<X, Y>(x: X, y: Y) { … } }
// static func box<X, Y>(x: X, y: Y) -> Box

@Injectable
struct Pair<X, Y> { init<Z>(x: X, y: Y, z: Z) { … } }
// static func pair<X, Y, Z>(x: X, y: Y, z: Z) -> Pair<X, Y> where Injectable == Pair<X, Y>
```

## Constraints

You never restate the constraints written on the **type**. `where Injectable == Codec<E>`
makes `Codec<E>` well-formed, and being well-formed *is* satisfying the type's own
requirements — so they come back on their own, whatever form they were written in:

```swift
@Injectable struct Foo<A: Hashable, B> { … }             // identical
@Injectable struct Bar<A, B> where A: Hashable { … }     // identical
```

Zerk reads parameter *names* only, so those two are indistinguishable by the time anything
is emitted. Inline inheritance, composition (`A: Hashable & Codable`), associated-type
requirements (`where A.Element: Hashable`) and cross-parameter ones (`where A.Element == B`)
all survive the same way.

A constraint on the **provider's own** parameters is different, and it is the same
difference that governs inference: nothing in the return type mentions `Z`, so nothing
binds it and nothing re-derives it either. Those are carried onto the member, verbatim:

```swift
@Injectable
struct Adder<A: Hashable> {
    @InjectableProviding
    init<Z: Numeric>(a: A, z: Z) { … }
}
// static func adder<A, Z>(a: A, z: Z) -> Adder<A> where Injectable == Adder<A>, Z: Numeric
```

The key's binding and the provider's requirements share one `where` clause. A parameter's
`: Numeric` and a written `where Z: Numeric` mean the same thing to Swift, so both arrive
as requirements — and a requirement naming an associated type is copied exactly as you
wrote it, since Zerk reads syntax and cannot resolve one:

```swift
@InjectableProviding
init<Z: Collection>(z: Z) where Z.Element: Hashable { … }
// static func assocProv<Z>(z: Z) -> AssocProv where Z: Collection, Z.Element: Hashable
```

The same applies to a constraint an `@Injectable` function adds beyond what its produced
type declares — `@Injectable func makeBox<X: Hashable, Y>(…) -> Box<X, Y>` over a plain
`Box<X, Y>` has nothing to re-derive `X: Hashable`, so the member and its forwarding thunk
both carry it.

The type's parameters come first, then the provider's own.

The rule across all of these is Swift's own, reported at your declaration rather than in generated code: **every generic parameter the member declares must appear in its signature.** The return type supplies the ones a generic key carries; everything else has to arrive as an argument. A parameter nothing can infer is a build error. And because this key is concrete, it keeps its interjection point — unlike a generic key.

## A parameterized existential key

**Or the key can carry the parameters, with `parameterized: true`.** The protocol's primary associated types take the type's own parameters, so the specialization survives into the key instead of being erased:

```swift
protocol Boxable<X, Y> { associatedtype X; associatedtype Y }

@Injectable<any Boxable>(parameterized: true)
struct Box<X, Y>: Boxable {
    @InjectableProviding init(_ x: X, _ y: Y) { … }
}

Zerk<any Boxable<Int, String>>.inject(1, "a")   // any Boxable<Int, String>
```

It has to be asked for: the same attribute without it means the opposite, and both are legal. The key cannot be written out in full — `@Injectable<any Boxable<X, Y>>` is rejected by Swift itself, since an attribute is resolved outside the declaration's scope.

Three things are checked: the type must be generic, the key must be spelled `any P` (Zerk never *adds* `any` — it cannot tell a protocol from a class), and the protocol's primary associated types must be as many as the type's parameters. The conformance must also map them positionally; Zerk reads syntax and cannot check that, so a crossed-over conformance is a compile error on the generated member naming both real types.

Parameterized existentials arrived in iOS 16 / macOS 13, so the generated extension carries an `@available` attribute. The plugin cannot read your deployment target, so it is emitted unconditionally — which costs nothing if you deploy higher:

```swift
@available(iOS 16.0, macOS 13.0, macCatalyst 16.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
extension Zerk {
    nonisolated static func box<X, Y>(_ x: X, _ y: Y) -> any Boxable<X, Y> where Injectable == any Boxable<X, Y> {
        if let interjected = _$interjected() {
            return interjected
        }
        return Box(x, y)
    }

    nonisolated static func inject<X, Y>(_ x: X, _ y: Y) -> any Boxable<X, Y> where Injectable == any Boxable<X, Y> {
        box(x, y)
    }

}
```

## Interjecting a generic key

**Generic keys are interjectable per specialization.** The namespace extension cannot name the parameter, so the plugin declares a marker protocol the base type conforms to, and scopes the point by that:

```swift
protocol `_$ZerkInjectable_Cache` {}
extension Cache: `_$ZerkInjectable_Cache` {}
extension Zerk.Interjection where Injectable: `_$ZerkInjectable_Cache` {
    nonisolated var `cache`: Void {}
}
```

So both forms work, and each reaches exactly the specialization it names — `Cache<Int>` is untouched by a double registered for `Cache<String>`:

```swift
#Interject(\.cache, with: Cache<String>(…))
#Interject<Cache<String>>(with: …)
```

There is no way to stand one double in for *every* specialization at once: a closure cannot be generic, so the registration has to name the specialization it covers.

A **parameterized existential** key is the exception. An existential conforms to nothing, so it can have no marker and no point — it is reachable by key only, with `#Interject<any Boxable<Int, String>>(with:)`.

---

[← Table of contents](../TableOfContents.md)

**See also:** [`@Injectable`](../Macros%20and%20Markers/Injectable.md) · [`@Singleton`](../Macros%20and%20Markers/Singleton.md) · [`@InjectableValue`](../Macros%20and%20Markers/InjectableValue.md) · [Foreign types](ForeignTypes.md) · [Generated code](../Plugin/GeneratedCode.md) · [Diagnostics](../Plugin/Diagnostics.md) · [Interjection](../Testing/Interjection.md)
