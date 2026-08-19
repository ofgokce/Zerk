//
//  ConstructionLog.swift
//  Zerk
//

import Foundation
import Testing
import Zerk

/// Counts fixture constructions **per test**, so asserting on them does not
/// require the suite to be serialized.
///
/// The fixtures here are resolved through one process-wide graph, so a naive
/// `static var createdCount` is shared by every test that touches the same
/// injectable. That was handled by serializing the suite and zeroing the
/// counters at the top of each test — which works only as far as a suite
/// reaches. `.serialized` orders a suite's own tests and nothing more, and Swift
/// Testing runs *suites* in parallel, so a fixture resolved from two suites
/// still raced. The old comments in `IntegrationFixtures` said as much.
///
/// A task local fixes both at once. Swift Testing runs each test in its own
/// task, and the constructions being counted all happen synchronously inside the
/// test body, so each test sees exactly its own — whatever else is running.
/// Nothing needs resetting, because nothing is shared.
///
/// What it cannot count is anything built *outside* a test's task: a
/// `@Singleton`'s storage may have been initialized by whoever touched it first.
/// That is a property of the thing being tested, not a limitation to work
/// around — assert on identity there instead, which is the real claim anyway.
enum ConstructionLog {

    /// One test's tally.
    ///
    /// Locked even though it is per task: a fixture is free to construct
    /// dependencies concurrently, and a dictionary mutated from two threads
    /// corrupts rather than merely miscounts.
    final class Counts: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String: Int] = [:]

        func record(_ name: String) {
            lock.withLock { storage[name, default: 0] += 1 }
        }

        func count(_ name: String) -> Int {
            lock.withLock { storage[name] ?? 0 }
        }

        /// Every name recorded, in no particular order. For assertions about
        /// *which* things were built rather than how many.
        var names: [String] {
            lock.withLock { Array(storage.keys) }
        }
    }

    @TaskLocal static var current: Counts?

    /// Records one construction against the running test, or does nothing when
    /// there is no test — a fixture built outside one is not being counted by
    /// anybody.
    static func record(_ name: String) {
        current?.record(name)
    }

    /// The count for the running test. Zero outside one.
    static func count(_ name: String) -> Int {
        current?.count(name) ?? 0
    }
}

/// Gives each test its own ``ConstructionLog``.
///
/// `isRecursive` so that applying it to a suite scopes each *test* rather than
/// wrapping the suite in one — the same reasoning `ZerkInterjections` documents,
/// and for the same reason: per-suite would leave the tests inside sharing a
/// tally and put the serialization requirement straight back.
struct ConstructionCounting: TestTrait, SuiteTrait, TestScoping {

    var isRecursive: Bool { true }

    func provideScope(for test: Test,
                      testCase: Test.Case?,
                      performing function: () async throws -> Void) async throws {
        try await ConstructionLog.$current.withValue(ConstructionLog.Counts()) {
            try await function()
        }
    }
}

extension Trait where Self == ConstructionCounting {
    /// A fresh construction tally per test.
    static var counting: Self { ConstructionCounting() }
}

/// Proves the tally is per test rather than shared.
///
/// The two cases below are deliberately asymmetric: one resolves a `Logger`
/// once and expects one, the other resolves it twice and expects two. A shared
/// counter fails whichever runs second, in either order — so this catches a
/// regression to process-wide counting without depending on execution order.
@Suite("Construction log", .counting)
struct ConstructionLogTests {

    @Test("one resolution counts once")
    func countsOne() {
        _ = Zerk<Logger>.inject()
        #expect(ConstructionLog.count(Logger.name) == 1)
    }

    @Test("two resolutions count twice, in a tally of this test's own")
    func countsTwo() {
        _ = Zerk<Logger>.inject()
        _ = Zerk<Logger>.inject()
        // `Logger` is transient, so this is two constructions — and two only if
        // no other test's resolutions land in the same tally.
        #expect(ConstructionLog.count(Logger.name) == 2)
    }

    @Test("a name nothing recorded is zero, not absent")
    func unrecordedIsZero() {
        #expect(ConstructionLog.count("NeverBuilt") == 0)
    }
}
