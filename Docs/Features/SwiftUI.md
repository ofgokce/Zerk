# SwiftUI and `@Observable`

`@Injected` initializes a property's **storage**, through `@storageRestrictions(initializes:)`,
at the moment the enclosing value is initialized. Everything on this page follows from that one
fact: it works wherever the property is genuinely stored, and not where something else has
already claimed the storage.

## `@Observable`

`@Observable` rewrites every stored property into a computed one backed by generated storage.
A computed property has nothing for `@Injected` to initialize, so mark the dependency
`@ObservationIgnored`:

```swift
@Injectable
@Observable
final class FeedModel {
    @ObservationIgnored @Injected var serving: Serving

    var count = 0                       // still observed
}
```

`@ObservationIgnored` excludes the property from observation and leaves it stored, which is
exactly what `@Injected` needs. Nothing is lost: a dependency resolved once at initialization has
no changes for a view to observe. The rest of the type is observed as usual.

Without it, Zerk says so:

```
error: @Injected cannot resolve an observed property: @Observable rewrites it into a computed
       property, and @Injected initializes stored storage. Mark the property
       '@ObservationIgnored', which excludes it from observation and leaves it stored.
```

## Property wrappers

`@State`, `@StateObject`, `@ObservedObject`, `@Published` and `@Bindable` each own their storage,
so `@Injected` has none to initialize and the two cannot be combined. Hand the wrapper the
resolved value instead — its own initializer takes it:

```swift
struct FeedView: View {
    @State private var model = Zerk<FeedModel>.inject()
    @StateObject private var legacy = Zerk<LegacyModel>.inject()

    var body: some View { Text("\(model.count)") }
}
```

This is a plain expression in the wrapper's `init(wrappedValue:)`, so every wrapper rule still
applies — `@StateObject` still builds once for the view's lifetime, `@State` still owns its value.

Writing `@Injected` on a wrapped property is refused by name:

```
error: @Injected initializes a property's storage, and @StateObject owns storage of its own.
       Write '@StateObject var legacy = Zerk<Key>.inject()', which hands the wrapper the
       resolved value.
```

### Why not both

This is a Swift limit, not a Zerk one. A property wrapper puts its own parameter in the
synthesized memberwise initializer, and no macro role can add a default expression to a
declaration that already exists — so a wrapped property with `@Injected` would still demand the
wrapper's argument at every call site. Init-accessor coverage propagates for plain stored
properties, and does not for a wrapper's backing storage.

## Registering a view model

A view model is an injectable like any other, and `@Observable` composes with the rest:

```swift
@Injectable
@Observable
final class FeedModel {
    @ObservationIgnored @Injected var serving: Serving

    @InjectableProviding
    init() {}
}
```

`@Singleton` or `@Scoped` apply as they do anywhere else, if the model should outlive one view.

**See also:** [`@Injected`](../Macros%20and%20Markers/Injected.md) · [`@Injectable`](../Macros%20and%20Markers/Injectable.md) · [`@Singleton`](../Macros%20and%20Markers/Singleton.md) · [`@Scoped`](../Macros%20and%20Markers/Scoped.md) · [Concurrency](Concurrency.md) · [Diagnostics](../Plugin/Diagnostics.md)
