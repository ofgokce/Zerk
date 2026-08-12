//
//  ZerkAsyncBox.swift
//  Zerk
//

import Foundation

/// Storage for one kept instance whose construction is `async` or `throws`.
///
/// The synchronous counterpart to ``ZerkScopedBox`` and to a `@Singleton`'s
/// `static let`, and it exists because neither of those can await: a `static let`
/// initializer has no suspension point available to it, and `ZerkScopedBox` holds
/// its lock across `build()` — which is exactly what makes it exactly-once, and
/// exactly what a lock may not do across an `await`.
///
/// The plugin emits one of these per async kept type, in the same file-private
/// namespace its synchronous siblings use:
///
/// ```swift
/// private enum _$zerk_singletons {
///     nonisolated static let client = ZerkAsyncBox<Client>()
/// }
///
/// extension Zerk<Connecting> {
///     nonisolated static func client() async throws -> Connecting {
///         if let interjected = _$interjected(for: \.`client`) { return interjected }
///         return try await _$zerk_singletons.client.value { try await Client() }
///     }
/// }
/// ```
///
/// ## Exactly-once without holding a lock
///
/// The state machine is `empty → building → ready`, and the trick is *what* is
/// stored while building: the `Task` itself. The first caller starts it; every
/// caller that arrives while it runs awaits the same `Task` and so receives the
/// same instance. The lock is taken only to read or move the state, never across
/// the await.
///
/// That is structural rather than a rule to remember. `NSLock` is `noasync`, so
/// every critical section here *has* to be a synchronous method — an `async`
/// function cannot take the lock at all.
///
/// ## `Value: Sendable`, unlike the synchronous boxes
///
/// A `Task`'s result crosses concurrency domains by definition, so the standard
/// library requires it. In practice this excludes nothing worth keeping: a
/// global-actor-isolated class is implicitly `Sendable`, an `actor` is
/// `Sendable`, and the `@unchecked Sendable` a `@Singleton` already needs today
/// still applies. What it does exclude — a nonisolated, non-`Sendable` class —
/// is the one shape that should not be shared process-wide to begin with.
public final class ZerkAsyncBox<Value: Sendable>: @unchecked Sendable {

    /// The scope this box is cleared by, or `nil` for a `@Singleton`, which
    /// belongs to no scope and is never reset.
    public let scope: InjectionScope?

    private enum State {
        case empty
        case building(Task<Value, Error>)
        case ready(Value)
    }

    /// What ``value(_:)`` learned under the lock: either the answer, or the one
    /// build to join.
    private enum Entry {
        case ready(Value)
        case awaiting(Task<Value, Error>)
    }

    private let lock = NSLock()
    private var state: State = .empty

    /// A `@Singleton`'s box: kept for the life of the process.
    public init() {
        self.scope = nil
    }

    /// A `@Scoped` type's box, which registers so `Zerk.reset(_:)` can find it.
    /// See ``ZerkScopedBox/init(scope:)`` for why registration happens here.
    public init(scope: InjectionScope) {
        self.scope = scope
        ZerkScopeRegistry.shared.register(self)
    }

    /// The instance, building it with `build` if there is none.
    ///
    /// Concurrent callers join one build rather than racing: the first stores its
    /// `Task`, the rest await it. `build` runs wherever it hops to — the closure
    /// the plugin passes carries its own isolation — so a `@MainActor` type is
    /// still constructed on the main actor.
    public func value(_ build: @Sendable @escaping () async throws -> Value) async throws -> Value {
        switch entry(build) {
        case .ready(let value):
            return value
        case .awaiting(let task):
            do {
                let value = try await task.value
                publish(value, from: task)
                return value
            } catch {
                // The failure is not cached. A kept instance poisoned for the
                // process by one transient failure — a timed-out connection, a
                // file not yet written — is a worse default than letting the
                // next caller try again, and a caller that wants the failure
                // remembered can remember it.
                clear(task)
                throw error
            }
        }
    }

    /// The non-throwing form, so a provider that is merely `async` does not
    /// force `try` on every consumer.
    ///
    /// The `try!` is discharged by the signature: `build` cannot throw, so the
    /// task it feeds cannot fail, and the only error `value(_:)` propagates is
    /// the one `build` raised.
    public func value(_ build: @Sendable @escaping () async -> Value) async -> Value {
        try! await value { () async throws -> Value in await build() }
    }

    /// Reads the state, starting the build if nothing else has.
    ///
    /// Synchronous, which is the point: it is the only place the lock is taken
    /// on the resolution path, and it cannot span a suspension.
    private func entry(_ build: @Sendable @escaping () async throws -> Value) -> Entry {
        lock.lock()
        defer { lock.unlock() }

        switch state {
        case .ready(let value):
            return .ready(value)
        case .building(let task):
            return .awaiting(task)
        case .empty:
            let task = Task { try await build() }
            state = .building(task)
            return .awaiting(task)
        }
    }

    /// Caches the built instance, unless a reset overtook the build.
    ///
    /// The task identity check is what makes ``reset()`` mean something while a
    /// build is in flight: without it, a build that started before the reset
    /// would publish afterwards and quietly undo it.
    private func publish(_ value: Value, from task: Task<Value, Error>) {
        lock.lock()
        defer { lock.unlock() }

        if case .building(let inFlight) = state, inFlight == task {
            state = .ready(value)
        }
    }

    private func clear(_ task: Task<Value, Error>) {
        lock.lock()
        defer { lock.unlock() }

        if case .building(let inFlight) = state, inFlight == task {
            state = .empty
        }
    }

    /// Drops the instance, so the next resolution builds a new one.
    ///
    /// Synchronous, like ``ZerkScopedBox/reset()``, which is what keeps
    /// `Zerk.reset(_:)` synchronous even for a scope holding async instances.
    /// An actor-based box could not offer this.
    ///
    /// A build already in flight is *not* cancelled: whoever is awaiting it still
    /// receives that instance. What the reset guarantees is that the instance is
    /// not kept — the next resolution starts a new build.
    public func reset() {
        lock.lock()
        let previous = state
        state = .empty
        lock.unlock()
        withExtendedLifetime(previous) {}
    }
}

extension ZerkAsyncBox: ZerkScopeResettable {
    var resetScope: InjectionScope? { scope }
}
