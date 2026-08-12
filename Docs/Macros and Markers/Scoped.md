# `@Scoped`

`@Scoped` keeps one instance of an injectable for as long as a named scope lasts, and drops
it when that scope is reset. This page covers the scope value, the storage Zerk generates,
what a reset does and does not reach, how each kind of consumer should hold a scoped instance,
and the two checks that stop something long-lived from keeping something short-lived.

Two unrelated things are called "scope" in Zerk. This page is about **injection scopes**,
which govern how long an instance is kept. An *interjection* scope is the test-isolation
boundary `#Interject` registers into — see [Scopes](../Testing/Scopes.md). They never
interact.

## What it does

`@Scoped(.session)` sits between the two lifetimes Zerk already had:

| | lifetime | storage |
|---|---|---|
| *(nothing)* | one instance per resolution | none |
| `@Scoped(.session)` | one instance until that scope is reset | `ZerkScopedBox` per type |
| `@Singleton` | one instance for the process | a `static let` per type |

```swift
extension InjectionScope {
    static let session = InjectionScope("session")
}

@Scoped(.session)
@Injectable<Caching>
final class SessionCache: Caching {
    @InjectableProviding
    init() {}
}
```

`Zerk<Caching>.inject()` now returns the same `SessionCache` every time — until:

```swift
func signOut() {
    credentials.clear()
    Zerk.reset(.session)
}
```

after which the next resolution builds a fresh one.

Everything else is unchanged: the same generated members, the same interjection point, the
same `inject()`. `@Scoped` decides how long the result is kept, not how it is reached.

## The scope

`InjectionScope` is an ordinary value, not a generic parameter and not a case of a closed
enum, so your app declares its own in an extension and a library can declare one without
either knowing about the other.

```swift
extension InjectionScope {
    static let session = InjectionScope("session")
    static let checkout = InjectionScope("checkout")
}
```

**The name is the identity.** Two `InjectionScope`s are the same scope when their names
match, whoever declared them — which is what makes a scope work across modules: a feature
module marks `@Scoped(.session)`, the app module calls `Zerk.reset(.session)`, and neither
holds a reference to the other's storage. The corollary is that the name is a shared
namespace, so pick one specific enough not to collide with some other module's.

**Write the name out.** There is no `#function` default, and that is deliberate: in a
computed `static var` it would yield the property name, but in a `static let` initializer —
the spelling most people reach for — it yields the enclosing *type* name.

```swift
static var a: InjectionScope { .init() }   // #function == "a"
static let b = InjectionScope()            // #function == "InjectionScope"
```

Every `static let` scope would then share one name, and `Zerk.reset(.session)` would silently
clear `.checkout` too. One repetition is cheaper than that.

**The attribute takes leading-dot form only.** `@Scoped(.session)` — not
`@Scoped(MyScopes.session)`, not `@Scoped(InjectionScope("session"))`. Zerk reads source and
never evaluates it, and `.session` is a token whose whole meaning is the member it names, so
it can both be echoed verbatim into the generated storage *and* compared against another
attribute's. Anything else is refused with that explanation.

## Storage

Scoped instances live in a generated `private enum _$zerk_scoped`, one `ZerkScopedBox` per
scoped *type*, and each `Zerk<Key>` member reads through it:

```swift
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
}
```

One box per type rather than per key, for the same reason `@Singleton` stores per type:
`Zerk<A>` and `Zerk<B>` are distinct generic specializations with distinct static storage, so
a box hung on them would exist once per key and "one instance" would only hold within a key.

Three things about that shape are worth knowing.

**The construction closure is at the member, not in the box.** The box stores no way to build
its value. That is what keeps the box `nonisolated` even when the type it holds is
`@MainActor` — the closure runs in whatever domain the *member* is isolated to — and it is
what keeps `reset` synchronous and callable from anywhere, since it only ever drops a
reference.

**The interjection guard runs first.** A double installed for the key is returned before the
box is consulted, so interjecting a scoped type never builds the real instance and never
leaves one cached. See [Interjection](../Testing/Interjection.md).

**The box slot carries an explicit isolation.** `ZerkScopedBox` is `Sendable`, so no
`nonisolated(unsafe)` is wanted, but the slot still has to be pinned or
`SWIFT_DEFAULT_ACTOR_ISOLATION` would make it `@MainActor` and put it out of reach of a
nonisolated member. It is pinned to the member's isolation, since that is the only thing that
reads it.

That last point has one consequence for you. Under an ambient global-actor default, a scope
declared as a plain `static let` is isolated to that actor, and a *nonisolated* scoped type's
box cannot read it. Declare the scope `nonisolated` and it works in every configuration:

```swift
extension InjectionScope {
    nonisolated static let session = InjectionScope("session")
}
```

## What a reset does

`Zerk.reset(.session)` drops Zerk's reference to every `.session` instance in the process,
across every module. `Zerk.resetAllScopes()` does it for every scope at once.

**It does not reach references already handed out.** Anything that resolved before the reset
keeps the instance it was given and goes on using it. That is the one thing about `@Scoped`
worth internalizing, because nothing about the call site makes it visible:

```swift
struct Feed {
    @Injected            var stored: SessionCache   // resolved once, at init
    @InjectedDynamically var live: SessionCache     // re-resolved on every read
}

Zerk.reset(.session)
// `stored` still hands back the pre-reset instance; `live` sees the new one.
```

The next section works through which of the two each kind of consumer wants.

**A resolution already in flight still caches its result.** Its build began before the box
was cleared. Resets are coarse lifecycle events — a logout, a tenant switch — so racing one
against live resolution of the thing being reset is an ordering problem at the call site
rather than something a finer lock could fix.

**The instance is released after the box's lock is dropped**, so a `deinit` runs on whichever
thread called `reset`, outside the lock.

## Consuming a scoped instance

Everything below resolves against this graph:

```swift
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

The question each consumer has to answer is only ever one: **do I outlive the scope?** If
not, nothing needs saying. If so, the reference has to be re-read rather than kept.

### A transient dependent needs nothing

An injectable with no lifetime of its own is rebuilt on every resolution, so it is handed the
current instance every time:

```swift
@Injectable
struct FeedLoader {
    @InjectableProviding
    init(cache: Caching) { … }
}
```

`Zerk<FeedLoader>.inject()` after a reset builds a `FeedLoader` around the *new* cache. There
is nothing to annotate and nothing that can go stale — this is the common case, and the
reason `@InjectedDynamically` is not the default.

### A consumer shorter-lived than the scope wants `@Injected`

A screen built per navigation, a request handler, a view model that dies with its view — all
of these are gone before the reset that would have invalidated them:

```swift
struct FeedScreen {
    @Injected var cache: Caching   // resolved once; this object will not outlive the session
}
```

One lookup, no per-access cost, and a reference that cannot change underneath it mid-render.

### A consumer longer-lived than the scope wants `@InjectedDynamically`

This is the case that bites, because the code looks identical and the bug only appears after
a logout:

```swift
@MainActor
final class AppCoordinator {
    @Injected            var atLaunch: Caching   // the *first* session's cache, forever
    @InjectedDynamically var current: Caching    // whatever session is current now
}
```

`atLaunch` is not wrong so much as pinned: it resolved once, at launch, and `Zerk.reset(_:)`
has no way to reach into it. `current` re-reads the box on every access, so it follows.

### A `@Singleton` must use it, and Zerk enforces that

A singleton outlives every scope by construction, so taking a scoped dependency as a
constructor parameter is refused at build time:

```swift
@Singleton
@Injectable
final class Analytics {
    @InjectableProviding
    init(cache: Caching) { … }   // error: @Singleton 'Analytics' depends on @Scoped(.session) 'SessionCache'
}
```

The fix the error names is to stop *capturing* it — hold it as a property resolved per use
instead:

```swift
@Singleton
@Injectable
final class Analytics {
    @InjectedDynamically var cache: Caching

    @InjectableProviding
    init() {}
}
```

The singleton is still one instance for the process; it simply no longer keeps a scoped one
alive inside itself. After `Zerk.reset(.session)` the same `Analytics` object reads the new
cache.

### In short

| the consumer | write | because |
|---|---|---|
| a transient injectable | a plain parameter | rebuilt per resolution, so always current |
| something the scope outlives | `@Injected` | it is gone before the reset matters |
| something that outlives the scope | `@InjectedDynamically` | a reset cannot reach a stored reference |
| a `@Singleton` | `@InjectedDynamically` | the only option — capturing one is a build error |
| something in the *same* scope | either | both are dropped by the same reset, so neither goes stale |

See [`@InjectedDynamically`](Injected.md#injecteddynamically) for its other forms — a stated
key, a key path, forwarded arguments — and for what a computed property costs you
(`var` only, no observers, no memberwise override).

## Staleness checks

Because a reset cannot reach what already captured an instance, something longer-lived than a
scope that *holds* a scoped instance will go quietly stale. Zerk reports two shapes of that,
and it reports them differently because it knows different amounts about them.

**A `@Singleton` holding a scoped instance is an error.** A singleton is built once and never
dropped, so it outlives every scope by construction — there is no configuration in which this
is what someone meant.

```
error: @Singleton 'Reporter' depends on @Scoped(.session) 'SessionCache'. A singleton is
built once and never dropped, so after that scope is reset it would still be holding the
instance from before. Give 'Reporter' the same @Scoped lifetime, or resolve the dependency
per use with @InjectedDynamically.
```

The fix is not to give up on the dependency — it is to stop capturing it. See
[a `@Singleton` must use it](#a-singleton-must-use-it-and-zerk-enforces-that) above for the
shape that satisfies this.

**A scope holding a different scope's instance is a warning.** Zerk can see the two scopes
are not the same one; it has no idea which is reset first, or whether either ever is.
`.request` inside `.session` is a bug; `.session` inside `.application` is fine. Only you
know which you wrote, so the build continues — narrow the lifetimes to one scope, or reach
for `@InjectedDynamically` as above.

Both checks reach *through* transient dependencies: a singleton that reaches a scoped
instance via two transient hops holds it just as firmly as one that names it outright. A
transient dependent needs no check at all — it is rebuilt on every resolution, so it can
never be the thing holding something stale. Two types in the same scope are likewise silent:
both are dropped by the same reset and both are rebuilt on the next resolution.

## Constraints

The rules `@Scoped` shares with `@Singleton`, and for the same reason — the instance is built
exactly once, with no help from the caller:

- **Reference types only** (`class` or `actor`). A value type is copied on every read, so
  keeping one for a scope would keep nothing.
- **No external arguments.** The instance is built once and handed to every caller, so there
  is no answer to which caller's arguments it was built with.
- **One provider across every key.** One instance cannot be built two ways.
- **Not on a generic type.** The box is a static stored property, which Swift does not allow
  in a generic type, so there is nowhere to keep one instance per specialization. Permanent,
  exactly as for `@Singleton`.

And one of its own:

- **Not with `@Singleton`.** Both say how long one instance is kept, and they disagree.

`@Scoped` works on a [foreign-type registration](../Features/ForeignTypes.md) too. Zerk reads
syntax and cannot tell a class from a struct it never sees, so the reference-type check is not
made there — your word is taken, exactly as `@Isolated`'s is.

## Isolation

A `@MainActor` scoped type works, and the arrangement that makes it work is worth stating:
`ZerkScopedBox.value` is nonisolated and takes a non-`Sendable`, non-escaping closure, so the
closure runs synchronously in the caller's domain. A synchronous nonisolated function does
not switch isolation, so a `@MainActor` member builds its `@MainActor` instance on the main
actor, inside the box's lock.

An `async` or `throws` provider is allowed, and changes the storage: `ZerkScopedBox` builds
under its lock, which cannot span an `await`, so such an instance is kept in a `ZerkAsyncBox`
instead. Same scope, same reset — but reading it becomes `async`, and the construction hops
into its own domain rather than inheriting the member's, because the box's closure is
`@Sendable`. See [Concurrency](../Features/Concurrency.md#kept-instances-that-have-to-await).

A scoped instance that crosses an isolation boundary must be `Sendable`, exactly as a
singleton must — it is shared, so its region is not disconnected. Zerk emits the same
explanatory `Sendable` check where that happens rather than constraining the box. See
[Concurrency](../Features/Concurrency.md).

## The macro

Inert. It expands to nothing and reports nothing, exactly like `@Singleton`, because whether
a scoped instance can be built depends on its whole dependency subtree rather than on the one
declaration a macro is handed. Every check above lives in the plugin.

---

[← Table of contents](../TableOfContents.md)

**See also:** [`@Singleton`](Singleton.md) · [`@Injected`](Injected.md) · [`@Injectable`](Injectable.md) · [Concurrency](../Features/Concurrency.md) · [Diagnostics](../Plugin/Diagnostics.md) · [Generated code](../Plugin/GeneratedCode.md) · [Interjection](../Testing/Interjection.md)
