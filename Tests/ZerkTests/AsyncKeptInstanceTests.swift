//
//  AsyncKeptInstanceTests.swift
//  Zerk
//

import Testing
import Zerk

/// What `ZerkAsyncBox` promises, against the real generated code.
///
/// The codegen side is covered in `ZerkInjectionCodegenTests`; this is the half
/// a golden string cannot reach — that concurrent callers get *one* instance,
/// that a failed build is not remembered, and that a reset still works while a
/// build is in flight.
///
/// `.serialized` because the fixtures' construction counts are process-wide, as
/// the storage under test is. Each test resets what it is about to assert on.
@Suite("Async kept instances", .serialized)
struct AsyncKeptInstanceTests {

    @Test("concurrent callers of an async singleton share one instance")
    func concurrentCallersShareOneInstance() async {
        // Whatever built it first, every caller from here on gets that one —
        // which is the claim, and is why identity is asserted rather than the
        // build count, which another suite may already have moved.
        let first = await Zerk<AsyncConnecting>.inject()

        let instances = await withTaskGroup(of: ObjectIdentifier.self) { group in
            for _ in 0..<50 {
                group.addTask { ObjectIdentifier(await Zerk<AsyncConnecting>.inject() as AnyObject) }
            }
            var seen = Set<ObjectIdentifier>()
            for await id in group { seen.insert(id) }
            return seen
        }

        #expect(instances == [ObjectIdentifier(first as AnyObject)])
    }

    @Test("a kept instance racing from cold builds exactly once")
    func coldRaceBuildsOnce() async {
        // The cold path is only observable through a scope, since a singleton
        // cannot be cleared — so this races an untouched *scoped* box instead,
        // which has the same coordination.
        Zerk.reset(.fixtureAsyncSession)
        AsyncBuildLog.shared.reset()

        let instances = await withTaskGroup(of: ObjectIdentifier.self) { group in
            for _ in 0..<50 {
                group.addTask { ObjectIdentifier(await Zerk<AsyncSession>.inject()) }
            }
            var seen = Set<ObjectIdentifier>()
            for await id in group { seen.insert(id) }
            return seen
        }

        #expect(instances.count == 1)
        #expect(AsyncBuildLog.shared.count("AsyncSession") == 1)
    }

    @Test("resetting a scope clears an async box like any other")
    func resetClearsAnAsyncBox() async {
        Zerk.reset(.fixtureAsyncSession)

        let before = await Zerk<AsyncSession>.inject()
        let again = await Zerk<AsyncSession>.inject()
        #expect(before === again)

        // Synchronous, from a nonisolated context, with no `await` — which is
        // the property the lock-based box exists to keep. An actor-based one
        // would have forced `Zerk.reset(_:)` to become async.
        Zerk.reset(.fixtureAsyncSession)

        let after = await Zerk<AsyncSession>.inject()
        #expect(after !== before)
    }

    @Test("a reset during a build does not undo itself")
    func resetDuringBuildIsNotOverwritten() async {
        Zerk.reset(.fixtureAsyncSession)

        // Start a build, reset while it is still suspended, then resolve again.
        async let inFlight = Zerk<AsyncSession>.inject()
        try? await Task.sleep(for: .milliseconds(5))
        Zerk.reset(.fixtureAsyncSession)

        let started = await inFlight
        let afterReset = await Zerk<AsyncSession>.inject()

        // The in-flight caller still receives what it was building — it is not
        // cancelled — but that instance was not kept, so the next resolution
        // built a fresh one.
        #expect(afterReset !== started)

        // And the fresh one *is* kept: the stale build must not publish over it.
        let settled = await Zerk<AsyncSession>.inject()
        #expect(settled === afterReset)
    }

    @Test("a failed build is not remembered")
    func failedBuildIsNotCached() async throws {
        Zerk.reset(.fixtureFlaky)
        AsyncBuildLog.shared.reset()
        FlakyGate.shared.shouldFail = true
        defer { FlakyGate.shared.shouldFail = false }

        await #expect(throws: FlakyGate.Failure.self) {
            _ = try await Zerk<FlakyResource>.inject()
        }
        await #expect(throws: FlakyGate.Failure.self) {
            _ = try await Zerk<FlakyResource>.inject()
        }
        // Two attempts, not one silently-cached failure.
        #expect(AsyncBuildLog.shared.count("FlakyResource") == 2)

        FlakyGate.shared.shouldFail = false
        let resource = try await Zerk<FlakyResource>.inject()
        let again = try await Zerk<FlakyResource>.inject()

        // And once it succeeds it is kept, like any other kept instance.
        #expect(resource === again)
    }

    /// The two overloads share one box, so a non-throwing call can *join* a
    /// build some other caller started with a throwing closure. Force-unwrapping
    /// there trapped: the error was never ours to rule out.
    @Test("the non-throwing overload survives joining a failed build")
    func nonThrowingOverloadDoesNotTrapOnAJoinedFailure() async throws {
        struct Failure: Error {}
        let box = ZerkAsyncBox<Int>()

        let failing = Task {
            try? await box.value { () async throws -> Int in
                try await Task.sleep(for: .milliseconds(120))
                throw Failure()
            }
        }
        // Long enough that the throwing build is still in flight to be joined.
        try await Task.sleep(for: .milliseconds(20))

        let value = await box.value { 7 }
        _ = await failing.value

        // Its own build cannot fail, so it always produces a value.
        #expect(value == 7)
    }

    @Test("a non-Sendable instance can be kept across an await")
    func nonSendableInstanceIsKept() async {
        let first = await Zerk<NonSendableAsyncClient>.inject()
        let again = await Zerk<NonSendableAsyncClient>.inject()

        #expect(first === again)
    }

    @Test("concurrent callers of a failing build all see the failure")
    func failureReachesEveryWaiter() async {
        AsyncBuildLog.shared.reset()
        Zerk.reset(.fixtureFlaky)
        FlakyGate.shared.shouldFail = true
        defer { FlakyGate.shared.shouldFail = false }

        let failures = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    do { _ = try await Zerk<FlakyResource>.inject(); return false }
                    catch { return true }
                }
            }
            var count = 0
            for await didThrow in group where didThrow { count += 1 }
            return count
        }

        #expect(failures == 20)
    }
}
