//
//  ScopingFixtures.swift
//  Zerk
//

import Zerk

// Fixtures for `@Scoped` and `@InjectedDynamically`, exercised by `ScopingTests`.
//
// Kept in their own file with their own scopes so nothing here can be cleared by
// a reset in another test. `Zerk.reset(_:)` reaches every box in the process, so
// a scope shared with another fixture would make the two suites able to break
// each other from a distance.

extension InjectionScope {
    // `nonisolated` because the boxes that name these are, and a nonisolated
    // slot cannot read an isolated scope. Explicit rather than incidental: this
    // target has no ambient default today, but a scope declaration that only
    // works while that stays true is a trap for whoever changes it.
    nonisolated static let fixtureSession = InjectionScope("zerk.tests.session")
    nonisolated static let fixtureCheckout = InjectionScope("zerk.tests.checkout")
}

protocol SessionScoped: AnyObject {
    var serial: Int { get }
}

/// Counts its own construction, so a test can tell "the same instance" from "an
/// equal one" without relying on identity alone.
@Scoped(.fixtureSession)
@Injectable<SessionScoped>
final class ScopedCache: SessionScoped {
    // Process-wide on purpose, unlike `ConstructionLog`: what is under test is
    // a *scope*, which is itself process-wide, so a per-test tally would not be
    // measuring the thing. `ScopingTests` is `.serialized` for the same reason,
    // and every test resets the scope before asserting rather than assuming a
    // starting value.
    nonisolated(unsafe) static var buildCount = 0
    let serial: Int

    @InjectableProviding
    init() {
        Self.buildCount += 1
        self.serial = Self.buildCount
    }
}

/// A second type in the same scope, to prove a reset clears the whole scope
/// rather than one box.
@Scoped(.fixtureSession)
@Injectable
final class ScopedSibling {
    nonisolated(unsafe) static var buildCount = 0
    let serial: Int

    @InjectableProviding
    init() {
        Self.buildCount += 1
        self.serial = Self.buildCount
    }
}

/// In a *different* scope, to prove a reset does not reach past its own.
@Scoped(.fixtureCheckout)
@Injectable
final class CheckoutBasket {
    nonisolated(unsafe) static var buildCount = 0
    let serial: Int

    @InjectableProviding
    init() {
        Self.buildCount += 1
        self.serial = Self.buildCount
    }
}

/// Depends on a scoped instance without being scoped itself: rebuilt per
/// resolution, so it always carries whatever the scope holds *now*.
@Injectable
struct TransientConsumer {
    let cacheSerial: Int

    @InjectableProviding
    init(cache: SessionScoped) {
        self.cacheSerial = cache.serial
    }
}

/// The two halves of the `@InjectedDynamically` story, side by side on one type so a
/// test can read both across a single reset.
struct ScopeHolder {
    @Injected var stored: SessionScoped
    @InjectedDynamically var live: SessionScoped
}

/// `@InjectedDynamically` in its other spellings, to prove they mean here what they
/// mean on `@Injected`.
extension Zerk<SessionScoped> {
    /// A member that is deliberately *not* the key's primary, for the key-path
    /// form to name.
    nonisolated static var pinned: SessionScoped { PinnedCache() }
}

final class PinnedCache: SessionScoped {
    let serial = -1
}

/// A parametric provider, so the argument-forwarding form has something to
/// forward to. The plugin emits a `DynamicInjected(seed:)` overload beside the
/// `Injected(seed:)` one; this is what proves the emitted overload is usable and
/// not merely present.
@Injectable
struct ScopedSeed {
    let value: Int

    @InjectableProviding
    init(seed: Int) { self.value = seed }
}

struct DynamicSpellings {
    @InjectedDynamically(\.pinned) var pinned: SessionScoped
    @InjectedDynamically<SessionScoped> var keyed: SessionScoped
    @InjectedDynamically var optional: SessionScoped?
    @InjectedDynamically(seed: 100) var seeded: ScopedSeed
}

/// The shape the documentation leads with: something that outlives a session
/// holding both a captured reference and a live one, under a global actor.
@MainActor
final class ScopeCoordinator {
    @Injected            var atLaunch: SessionScoped
    @InjectedDynamically var current: SessionScoped
}

protocol Repositorying: AnyObject {}

/// Counted so a test can tell whether interjecting the scoped type that depends
/// on it skipped building it as well.
@Injectable
struct ScopedDependency {
    nonisolated(unsafe) static var buildCount = 0

    @InjectableProviding
    init() { Self.buildCount += 1 }
}

@Scoped(.fixtureSession)
@Injectable<Repositorying>
final class ScopedRepository: Repositorying {
    @InjectableProviding
    init(dependency: ScopedDependency) {}
}

/// Keyed by the protocol so a double needs none of the real type's dependencies.
final class FakeRepository: Repositorying {}

/// The documented way out of the `@Singleton` → `@Scoped` build error: hold the
/// dependency as a property resolved per use, rather than capturing one at init.
///
/// The singleton itself still outlives every scope — that is the point of it —
/// but it no longer *keeps* a scoped instance, so there is nothing to go stale.
@Singleton
@Injectable
final class ScopeObservingSingleton {
    @InjectedDynamically var cache: SessionScoped

    @InjectableProviding
    init() {}
}

/// A `@MainActor` scoped type. The box slot is isolated to match, and the
/// construction closure runs on the main actor because the member does.
@MainActor
@Scoped(.fixtureSession)
@Injectable
final class IsolatedScopedModel {
    nonisolated(unsafe) static var buildCount = 0
    let serial: Int

    @InjectableProviding
    init() {
        Self.buildCount += 1
        self.serial = Self.buildCount
    }
}
