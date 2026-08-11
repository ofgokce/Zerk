//
//  ScopingTests.swift
//  Zerk
//

import Testing
@testable import Zerk

/// `@Scoped` and `@InjectedDynamically` against the real macros, the real plugin and
/// the real runtime.
///
/// `.serialized`, and not incidentally. A scope is process-wide by design —
/// that is what lets an app module reset a scope a feature module declared — so
/// two tests resetting the same scope in parallel would clear each other's
/// instances. The fixtures use scopes nothing else touches; this keeps the tests
/// in this suite from touching each other.
@Suite("Scoping", .serialized)
struct ScopingTests {

    // MARK: - Keeping

    @Test("a scoped injectable is built once and handed back")
    func keepsOneInstance() {
        Zerk.reset(.fixtureSession)
        let before = ScopedCache.buildCount

        let first = Zerk<SessionScoped>.inject()
        let second = Zerk<SessionScoped>.inject()

        #expect(first === second)
        #expect(ScopedCache.buildCount == before + 1)
    }

    @Test("resetting the scope builds a new one on the next resolution")
    func resetRebuilds() {
        Zerk.reset(.fixtureSession)
        let first = Zerk<SessionScoped>.inject()

        Zerk.reset(.fixtureSession)
        let second = Zerk<SessionScoped>.inject()

        #expect(first !== second)
        #expect(second.serial == first.serial + 1)
    }

    @Test("a reset that nothing resolves after it builds nothing")
    func resetIsLazy() {
        Zerk.reset(.fixtureSession)
        _ = Zerk<SessionScoped>.inject()
        let after = ScopedCache.buildCount

        Zerk.reset(.fixtureSession)
        Zerk.reset(.fixtureSession)

        // Reset drops the instance; it does not eagerly replace it.
        #expect(ScopedCache.buildCount == after)
    }

    @Test("a reset clears every box in the scope, not just one")
    func resetClearsWholeScope() {
        Zerk.reset(.fixtureSession)
        let cache = Zerk<SessionScoped>.inject()
        let sibling = Zerk<ScopedSibling>.inject()

        Zerk.reset(.fixtureSession)

        #expect(Zerk<SessionScoped>.inject() !== cache)
        #expect(Zerk<ScopedSibling>.inject() !== sibling)
    }

    @Test("a reset does not reach another scope")
    func resetIsScoped() {
        Zerk.reset(.fixtureSession)
        Zerk.reset(.fixtureCheckout)

        let basket = Zerk<CheckoutBasket>.inject()
        Zerk.reset(.fixtureSession)

        #expect(Zerk<CheckoutBasket>.inject() === basket)
    }

    @Test("resetAllScopes clears every scope at once")
    func resetAllClearsEverything() {
        let cache = Zerk<SessionScoped>.inject()
        let basket = Zerk<CheckoutBasket>.inject()

        Zerk.resetAllScopes()

        #expect(Zerk<SessionScoped>.inject() !== cache)
        #expect(Zerk<CheckoutBasket>.inject() !== basket)
    }

    @Test("an unknown scope resets nothing")
    func unknownScopeIsInert() {
        Zerk.reset(.fixtureSession)
        let cache = Zerk<SessionScoped>.inject()

        Zerk.reset(InjectionScope("nothing.declares.this"))

        #expect(Zerk<SessionScoped>.inject() === cache)
    }

    @Test("a transient dependent picks up the current scoped instance")
    func transientSeesCurrentInstance() {
        Zerk.reset(.fixtureSession)
        let first = Zerk<TransientConsumer>.inject()
        #expect(first.cacheSerial == Zerk<SessionScoped>.inject().serial)

        Zerk.reset(.fixtureSession)
        let second = Zerk<TransientConsumer>.inject()

        // Rebuilt per resolution, so it never holds a stale one.
        #expect(second.cacheSerial != first.cacheSerial)
    }

    @Test("a global-actor-isolated scoped type is kept the same way")
    @MainActor
    func isolatedScopedIsKept() {
        Zerk.reset(.fixtureSession)
        let first = Zerk<IsolatedScopedModel>.inject()
        #expect(Zerk<IsolatedScopedModel>.inject() === first)

        Zerk.reset(.fixtureSession)
        #expect(Zerk<IsolatedScopedModel>.inject() !== first)
    }

    // MARK: - @InjectedDynamically

    @Test("@Injected keeps what it resolved; @InjectedDynamically follows the reset")
    func dynamicFollowsTheReset() {
        Zerk.reset(.fixtureSession)
        let holder = ScopeHolder()
        let storedSerial = holder.stored.serial
        #expect(holder.live.serial == storedSerial)

        Zerk.reset(.fixtureSession)

        // The stored one was resolved at init and is still the old instance…
        #expect(holder.stored.serial == storedSerial)
        // …while the dynamic one re-resolves and sees the replacement.
        #expect(holder.live.serial != storedSerial)
    }

    @Test("@InjectedDynamically resolves on every access, not once per holder")
    func dynamicReResolvesEachRead() {
        Zerk.reset(.fixtureSession)
        let holder = ScopeHolder()
        let first = holder.live.serial

        Zerk.reset(.fixtureSession)
        let second = holder.live.serial
        Zerk.reset(.fixtureSession)
        let third = holder.live.serial

        #expect(first != second)
        #expect(second != third)
    }

    @Test("@InjectedDynamically takes a key path, a key, and an optional")
    func dynamicSpellings() {
        Zerk.reset(.fixtureSession)
        let spellings = DynamicSpellings()

        // The key-path form reaches the named member, not the primary.
        #expect(spellings.pinned.serial == -1)
        // The stated-key form resolves the key's primary.
        #expect(spellings.keyed === Zerk<SessionScoped>.inject())
        // Optionality belongs to the property; the key is the unwrapped type.
        #expect(spellings.optional != nil)
        // Arguments forward into `inject(seed:)`, through the overload the
        // plugin emits for the dynamic attribute as well as the stored one.
        #expect(spellings.seeded.value == 100)
    }

    @Test("the documented coordinator shape behaves as documented")
    @MainActor
    func coordinatorKeepsOneAndFollowsTheOther() {
        Zerk.reset(.fixtureSession)
        let coordinator = ScopeCoordinator()
        let launchSerial = coordinator.atLaunch.serial

        Zerk.reset(.fixtureSession)

        #expect(coordinator.atLaunch.serial == launchSerial)
        #expect(coordinator.current.serial != launchSerial)
    }

    @Test("a singleton reads the current scoped instance through @InjectedDynamically")
    func singletonFollowsTheScope() {
        Zerk.reset(.fixtureSession)
        let observer = Zerk<ScopeObservingSingleton>.inject()
        let first = observer.cache.serial

        Zerk.reset(.fixtureSession)

        // The singleton is the same object — it outlives every scope — but the
        // dependency it reads is the post-reset one. Capturing it at init is
        // what the build error refuses, and this is the alternative it names.
        #expect(Zerk<ScopeObservingSingleton>.inject() === observer)
        #expect(observer.cache.serial != first)
    }

    @Test("interjecting a scoped key neither builds the real instance nor fills the box")
    func interjectionBypassesTheBox() {
        Zerk.reset(.fixtureSession)
        let before = ScopedCache.buildCount

        Zerk.withInterjections {
            #Interject<SessionScoped>(with: PinnedCache())
            #expect(Zerk<SessionScoped>.inject().serial == -1)
            #expect(Zerk<SessionScoped>.inject().serial == -1)
        }

        // The guard sits ahead of the box, so the real provider never ran…
        #expect(ScopedCache.buildCount == before)

        // …and the box was left empty rather than holding the double. Both
        // halves matter: a double cached in the box would outlive the scope that
        // registered it and leak into every test that ran afterwards.
        let real = Zerk<SessionScoped>.inject()
        #expect(real.serial != -1)
        #expect(ScopedCache.buildCount == before + 1)
        #expect(Zerk<SessionScoped>.inject() === real)
    }

    @Test("interjecting a kept instance skips its dependency subtree too")
    func interjectionSkipsTheSubtree() {
        Zerk.reset(.fixtureSession)
        let before = ScopedDependency.buildCount

        Zerk.withInterjections {
            #Interject<Repositorying>(with: FakeRepository())
            #expect(Zerk<Repositorying>.inject() is FakeRepository)
        }

        // Worth asserting because the general rule is the opposite: a
        // parameterized transient member takes its dependencies as *default
        // arguments*, which Swift evaluates before the body — so an interjected
        // one still builds its real subtree. A kept instance resolves inside the
        // box's closure instead, which the guard returns ahead of.
        #expect(ScopedDependency.buildCount == before)

        // And the real one still builds normally once nothing stands in.
        _ = Zerk<Repositorying>.inject()
        #expect(ScopedDependency.buildCount == before + 1)
    }

    @Test("a dynamic property is interjectable like any other resolution")
    func dynamicRespectsInterjection() {
        // The synchronous overload: nothing in the body suspends, and `await`
        // on a non-async closure is a warning.
        Zerk.withInterjections {
            let holder = ScopeHolder()
            #Interject<SessionScoped>(with: PinnedCache())
            // Read *after* interjecting: that is the point of resolving late.
            #expect(holder.live.serial == -1)
        }
    }
}
