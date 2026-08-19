//
//  AsyncKeptInstanceFixtures.swift
//  Zerk
//

import Foundation
import Zerk

// Fixtures for kept instances whose construction is `async` or `throws`,
// exercised by `AsyncKeptInstanceTests`.
//
// Their own scope, for the reason `ScopingFixtures` gives: `Zerk.reset(_:)`
// reaches every box in the process, so sharing a scope with another suite would
// let the two clear each other's instances from a distance.

extension InjectionScope {
    nonisolated static let fixtureAsyncSession = InjectionScope("zerk.tests.async.session")
    /// Its own scope so the failure tests can start cold without disturbing
    /// `AsyncSession` — a `@Singleton` would give them exactly one cold start
    /// for the whole process, which is one fewer than they need.
    nonisolated static let fixtureFlaky = InjectionScope("zerk.tests.async.flaky")
}

/// Counts constructions process-wide, like `ScopedCache` and for the same
/// reason: what is under test is storage shared across the process, so a
/// per-test tally would not be measuring it. `AsyncKeptInstanceTests` is
/// `.serialized` and resets before asserting.
nonisolated final class AsyncBuildLog: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    static let shared = AsyncBuildLog()

    func record(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        counts[name, default: 0] += 1
    }

    func count(_ name: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[name] ?? 0
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        counts.removeAll()
    }
}

protocol AsyncConnecting: Sendable {
    var serial: Int { get }
}

/// A `@Singleton` that has to suspend to build. One instance for the process,
/// whatever the concurrency.
@Singleton
@Injectable<AsyncConnecting>
final class AsyncClient: AsyncConnecting, @unchecked Sendable {
    let serial: Int

    @InjectableProviding
    init() async {
        AsyncBuildLog.shared.record("AsyncClient")
        // A real suspension, so concurrent callers genuinely overlap rather
        // than each finding the work already done.
        try? await Task.sleep(for: .milliseconds(30))
        self.serial = AsyncBuildLog.shared.count("AsyncClient")
    }
}

/// A `@Scoped` type that has to suspend to build, so a reset has something to
/// clear and the next resolution has something to rebuild.
@Scoped(.fixtureAsyncSession)
@Injectable
final class AsyncSession: @unchecked Sendable {
    let serial: Int

    @InjectableProviding
    init() async {
        AsyncBuildLog.shared.record("AsyncSession")
        try? await Task.sleep(for: .milliseconds(20))
        self.serial = AsyncBuildLog.shared.count("AsyncSession")
    }
}

/// Construction fails while `shouldFail` is set, so a test can prove a failure
/// is not cached.
nonisolated final class FlakyGate: @unchecked Sendable {
    private let lock = NSLock()
    private var failing = true

    static let shared = FlakyGate()

    struct Failure: Error {}

    var shouldFail: Bool {
        get { lock.lock(); defer { lock.unlock() }; return failing }
        set { lock.lock(); defer { lock.unlock() }; failing = newValue }
    }
}

/// A plain, non-`Sendable` class kept across an `await`.
///
/// Its existence is the test: gaining an `async` provider must not narrow what
/// may be kept, so this has to *compile*. A `Task`'s result must be `Sendable`,
/// which is why `ZerkAsyncBox` carries the value past that requirement rather
/// than constraining it — the synchronous slot accepts exactly this shape.
@Singleton
@Injectable
final class NonSendableAsyncClient {
    var mutable = 0

    @InjectableProviding
    init() async {}
}

@Scoped(.fixtureFlaky)
@Injectable
final class FlakyResource: @unchecked Sendable {
    let serial: Int

    @InjectableProviding
    init() throws {
        AsyncBuildLog.shared.record("FlakyResource")
        if FlakyGate.shared.shouldFail {
            throw FlakyGate.Failure()
        }
        self.serial = AsyncBuildLog.shared.count("FlakyResource")
    }
}
