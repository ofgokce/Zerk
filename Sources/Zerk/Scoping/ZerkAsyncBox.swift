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
/// ## `Sendable`, on the same terms as the synchronous boxes
///
/// A `Task`'s result must be `Sendable`, which would put a constraint on `Value`
/// that neither a `@Singleton`'s `static let` nor `ZerkScopedBox` imposes — so a
/// type that is kept perfectly well today would stop being keepable the moment
/// its provider gained an `async`. ``Payload`` carries the value past that
/// requirement instead, on exactly the contract the synchronous storage already
/// documents: a kept instance is shared, and sharing one *across isolation
/// domains* requires it to be `Sendable`. That is checked where it actually
/// happens, by the conformance check the plugin emits, rather than by
/// constraining every kept instance whether it crosses a domain or not.
public final class ZerkAsyncBox<Value>: @unchecked Sendable {

    /// Carries the built value out of the build task.
    ///
    /// `@unchecked` for the reason above, and no wider than the
    /// `nonisolated(unsafe)` a synchronous singleton's slot already carries.
    private struct Payload: @unchecked Sendable {
        let value: Value
    }

    /// The scope this box is cleared by, or `nil` for a `@Singleton`, which
    /// belongs to no scope and is never reset.
    public let scope: InjectionScope?

    private enum State {
        case empty
        case building(Task<Payload, Error>)
        case ready(Value)
    }

    /// What ``value(_:)`` learned under the lock: either the answer, or the one
    /// build to join.
    private enum Entry {
        case ready(Value)
        case awaiting(Task<Payload, Error>)
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
                let value = try await task.value.value
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
    /// It cannot simply force-unwrap the throwing form. The two share one box,
    /// so this call may *join* a build some other caller started with a closure
    /// that does throw — and then the error is not ours to have ruled out. The
    /// generator never mixes them on one box, but both overloads are public, so
    /// "cannot happen" would be a trap rather than an invariant.
    ///
    /// Retrying is the answer rather than propagating, because our own build
    /// cannot fail: a failure is never cached, so the next attempt either finds
    /// a value or starts our build, which will produce one.
    ///
    /// It retries a bounded number of times, and stops if the task is cancelled.
    /// Termination by argument — "someone else's build failed, ours cannot" —
    /// holds only when this caller then wins the race to the empty state, and a
    /// caller driving the throwing overload with a failing build in a loop can
    /// keep taking it. An unbounded wait would then hang a structured-concurrency
    /// scope with nothing observable, since the joined error is discarded.
    /// Falling back to building directly gives up exactly-once for this one
    /// call, which is the lesser failure.
    public func value(_ build: @Sendable @escaping () async -> Value) async -> Value {
        for _ in 0..<Self.joinAttempts {
            // Checked *inside* the loop, and after the cheap read below, because
            // a cancelled caller still owes its caller a value — and if the box
            // already holds one, that value is free. Skipping straight to the
            // fallback would rebuild an instance that exists, and hand back one
            // the box never published: for a `@Singleton`, a second instance
            // while the shared one sits cached.
            if case .ready(let value) = entry({ await build() }) {
                return value
            }
            if Task.isCancelled {
                break
            }
            if let value = try? await value({ () async throws -> Value in await build() }) {
                return value
            }
        }
        // Cancelled, or repeatedly overtaken. Either way this call still owes
        // its caller a value, and its own build is the one thing that cannot
        // fail to produce one.
        return await build()
    }

    /// See ``zerkAsyncBoxJoinAttempts``.
    private static var joinAttempts: Int { zerkAsyncBoxJoinAttempts }

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
            let task = Task { Payload(value: try await build()) }
            state = .building(task)
            return .awaiting(task)
        }
    }

    /// Caches the built instance, unless a reset overtook the build.
    ///
    /// The task identity check is what makes ``reset()`` mean something while a
    /// build is in flight: without it, a build that started before the reset
    /// would publish afterwards and quietly undo it.
    private func publish(_ value: Value, from task: Task<Payload, Error>) {
        lock.lock()
        defer { lock.unlock() }

        if case .building(let inFlight) = state, inFlight == task {
            state = .ready(value)
        }
    }

    private func clear(_ task: Task<Payload, Error>) {
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

/// How many times a non-throwing `value(_:)` re-joins another caller's build
/// before building on its own.
///
/// Small on purpose: each attempt means someone else's build failed in the
/// window, which is already the unusual case.
///
/// A file-scope constant rather than a static on the box, because a generic type
/// cannot hold a static stored property — and a computed `var` returning a
/// literal reads as something that might vary per call or per instance, which is
/// the question a reader tuning a retry bound would ask.
private let zerkAsyncBoxJoinAttempts = 4
