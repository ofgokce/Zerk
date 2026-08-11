//
//  ZerkScopedBox.swift
//  Zerk
//

import Foundation

/// Storage for one `@Scoped` type's instance: built on first resolution, handed
/// out unchanged until its scope is reset, then built again on the next
/// resolution.
///
/// The plugin emits one of these per scoped type, in a file-private namespace,
/// and every generated member for that type reads through it:
///
/// ```swift
/// private enum _$zerk_scoped {
///     static let sessionCache = ZerkScopedBox<SessionCache>(scope: .session)
/// }
///
/// extension Zerk<Caching> {
///     nonisolated static var sessionCache: Caching {
///         if let interjected = _$interjected(for: \.`sessionCache`) { return interjected }
///         return _$zerk_scoped.sessionCache.value { SessionCache() }
///     }
/// }
/// ```
///
/// ## Why the construction closure lives at the member
///
/// The box stores no way to build its value. That is deliberate, and it is what
/// keeps three things simple at once:
///
/// - the box is `nonisolated` even when the type it holds is `@MainActor`,
///   because the closure is passed in from — and runs in — whatever domain the
///   generated member is isolated to;
/// - ``reset()`` is synchronous and callable from anywhere, since it only drops
///   a reference and never has to rebuild;
/// - rebuilding after a reset happens at the next access, in that access's
///   domain, rather than at reset time in the resetter's.
///
/// ## `@unchecked Sendable`
///
/// The lock protects the box, but `Value` itself may not be `Sendable` — the
/// same situation `@Singleton` is in, and the same documented contract: a
/// scoped instance is shared, so sharing it across isolation domains requires
/// it to be `Sendable`, and the plugin emits a `Sendable` check where that
/// actually happens rather than constraining the box.
public final class ZerkScopedBox<Value>: @unchecked Sendable {

    /// The scope this box is cleared by. Read by ``ZerkScopeRegistry`` when
    /// `Zerk.reset(_:)` decides which boxes a reset reaches.
    public let scope: InjectionScope

    private let lock = NSLock()
    private var cached: Value?

    /// Registers with ``ZerkScopeRegistry`` so `Zerk.reset(_:)` can find it.
    ///
    /// Registration happens here rather than on first caching because the boxes
    /// are `static let`s: the initializer runs exactly once, the first time
    /// anything touches the storage, which is the same moment a
    /// register-on-first-use scheme would have fired.
    public init(scope: InjectionScope) {
        self.scope = scope
        ZerkScopeRegistry.shared.register(self)
    }

    /// The instance for this scope, building it with `build` if there is none.
    ///
    /// `build` runs **while the lock is held**, so the instance is constructed
    /// exactly once however many callers race — which is the whole claim
    /// `@Scoped` makes. Building outside the lock would be deadlock-proof but
    /// would let two threads both run a constructor whose side effects are
    /// visible, and only one of the two results would survive.
    ///
    /// Holding a lock across arbitrary user code is safe here because the only
    /// way to re-enter *this* box from inside `build` is a dependency cycle, and
    /// the plugin rejects those at build time. Reaching a *different* scoped
    /// box takes a different lock, and a cycle between two boxes is likewise a
    /// build error.
    public func value(_ build: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        if let cached {
            return cached
        }
        let built = build()
        cached = built
        return built
    }

    /// Drops the instance, so the next resolution builds a new one.
    ///
    /// The old value is released *after* the lock is dropped: a `deinit` is
    /// arbitrary user code, and running it under the lock would put the same
    /// re-entrancy question back that ``value(_:)`` answers by construction.
    ///
    /// Note this releases Zerk's reference and nothing else. Anything already
    /// handed the old instance — an `@Injected` property resolved before the
    /// reset, a captured reference — keeps it alive and keeps using it. See
    /// `@InjectedDynamically` for the property form that re-resolves.
    public func reset() {
        lock.lock()
        let previous = cached
        cached = nil
        lock.unlock()
        withExtendedLifetime(previous) {}
    }
}

/// What ``ZerkScopeRegistry`` needs from a box, which is the part that does not
/// mention `Value`.
///
/// The registry holds boxes of every type at once, so it holds them as
/// existentials — and a `ZerkScopedBox<Value>` cannot be one of those while
/// `Value` is in the way.
protocol ZerkScopeResettable: AnyObject, Sendable {
    var scope: InjectionScope { get }
    func reset()
}

extension ZerkScopedBox: ZerkScopeResettable {}

/// Every ``ZerkScopedBox`` in the process, so `Zerk.reset(_:)` can reach the
/// ones a scope owns.
///
/// A registry is what makes a reset work at all. The generated storage is
/// file-private to the file that declares it — deliberately, so nothing reaches
/// a module's instances behind its back — which leaves nothing for
/// `Zerk.reset(_:)` in the `Zerk` module to enumerate. Boxes announcing
/// themselves as they come into existence closes that, and closes it across
/// module boundaries at the same time: an app resets a scope that a feature
/// module declared without either naming the other.
final class ZerkScopeRegistry: @unchecked Sendable {

    static let shared = ZerkScopeRegistry()

    private let lock = NSLock()
    private var boxes: [any ZerkScopeResettable] = []

    /// Strongly held, and never removed. The boxes are `static let`s and so live
    /// as long as the process; the list is bounded by the number of `@Scoped`
    /// declarations in the build.
    func register(_ box: any ZerkScopeResettable) {
        lock.lock()
        defer { lock.unlock() }
        boxes.append(box)
    }

    /// Clears every box belonging to `scope`.
    ///
    /// The list is snapshotted and the registry lock dropped **before** any box
    /// is reset, which is load-bearing rather than tidy. Resetting under the
    /// registry lock takes the two locks in the order (registry, box), while a
    /// resolution that constructs a dependency takes them in the order (box,
    /// registry) — the box is locked for the build, and the build touches
    /// another scoped type whose box registers itself. Two orders, two threads,
    /// one deadlock. Snapshotting means no thread ever holds both.
    ///
    /// A resolution already in flight when a reset lands still caches its
    /// result, since its build began before the box was cleared. Resets are
    /// coarse lifecycle events — a logout, a tenant switch — so racing one
    /// against live resolution of the thing being reset is the caller's
    /// ordering problem, not something a finer lock could fix.
    func reset(_ scope: InjectionScope) {
        lock.lock()
        let targets = boxes.filter { $0.scope == scope }
        lock.unlock()

        for box in targets {
            box.reset()
        }
    }

    /// Clears every box in every scope.
    func resetAll() {
        lock.lock()
        let targets = boxes
        lock.unlock()

        for box in targets {
            box.reset()
        }
    }
}

public extension Zerk where Injectable == Never {

    /// Drops every `@Scoped(scope)` instance, so the next resolution of each
    /// builds a fresh one.
    ///
    /// Spelled on `Zerk<Never>` so it reads as `Zerk.reset(.session)` without
    /// naming a key — a scope spans every key at once, exactly as
    /// ``Zerk/withInterjections(_:)`` does.
    ///
    /// ```swift
    /// func signOut() {
    ///     credentials.clear()
    ///     Zerk.reset(.session)
    /// }
    /// ```
    ///
    /// Only Zerk's own reference is dropped. A consumer that resolved before the
    /// reset keeps the instance it was given; `@InjectedDynamically` is the
    /// property form that picks up the replacement.
    static func reset(_ scope: InjectionScope) {
        ZerkScopeRegistry.shared.reset(scope)
    }

    /// Drops every scoped instance in the process, whatever scope it belongs to.
    ///
    /// Named for what it does rather than as `reset()`, which on `Zerk` would
    /// read as resetting the graph itself — there is no graph to reset, only
    /// these caches.
    static func resetAllScopes() {
        ZerkScopeRegistry.shared.resetAll()
    }
}
