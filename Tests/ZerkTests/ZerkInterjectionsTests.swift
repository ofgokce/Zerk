//
//  ZerkInterjectionsTests.swift
//  Zerk
//

import Testing
import ZerkTesting
@testable import Zerk

/// The trait gives every test its own scope, so `#Interject` works with no
/// `withInterjections` in sight — and nothing leaks between tests.
@Suite("Zerk interjections", .zerk)
struct ZerkInterjectionsTests {

    @Test("a scope is in force without asking for one")
    func scopeIsProvided() {
        #expect(ZerkInterjector.current !== ZerkInterjector.processDefault)
    }

    @Test("interjecting needs no explicit scope")
    func interjectsDirectly() {
        #Interject<Loading>(with: TraitMock(tag: "trait"))
        #expect((Zerk<Loading>.live as? TraitMock)?.tag == "trait")
    }

    // The two below run concurrently and interject the same key. Each must see
    // only its own — the point of `isRecursive`, which scopes per test rather
    // than once around the suite.
    @Test("parallel test A sees only its own double")
    func parallelA() async throws {
        #Interject<Loading>(with: TraitMock(tag: "A"))
        for _ in 0..<40 {
            #expect((Zerk<Loading>.live as? TraitMock)?.tag == "A")
            try await Task.sleep(nanoseconds: 100_000)
        }
    }

    @Test("parallel test B sees only its own double")
    func parallelB() async throws {
        #Interject<Loading>(with: TraitMock(tag: "B"))
        for _ in 0..<40 {
            #expect((Zerk<Loading>.live as? TraitMock)?.tag == "B")
            try await Task.sleep(nanoseconds: 100_000)
        }
    }

    @Test("a test that interjects nothing resolves the real graph")
    func untouchedResolvesReal() async throws {
        for _ in 0..<40 {
            #expect(Zerk<Loading>.live is TraitMock == false)
            try await Task.sleep(nanoseconds: 100_000)
        }
    }
}

/// Shared interjections: every test starts from the same doubles, and may
/// override them.
@Suite("Zerk interjections, shared", .zerk { #Interject<Loading>(with: TraitMock(tag: "shared")) })
struct SharedZerkInterjectionsTests {

    @Test("the shared interjections are in force")
    func sharedApply() {
        #expect((Zerk<Loading>.live as? TraitMock)?.tag == "shared")
    }

    @Test("a test can override them")
    func testOverridesShared() {
        #Interject<Loading>(with: TraitMock(tag: "own"))
        #expect((Zerk<Loading>.live as? TraitMock)?.tag == "own")
    }

    @Test("overriding in one test does not disturb another")
    func sharedSurviveElsewhere() async throws {
        for _ in 0..<40 {
            #expect((Zerk<Loading>.live as? TraitMock)?.tag == "shared")
            try await Task.sleep(nanoseconds: 100_000)
        }
    }
}

/// The named form, which is the point of the value being a trait: one set,
/// declared once, applied to as many suites as want it.
let sharedDoubles = ZerkInterjections {
    #Interject<Loading>(with: TraitMock(tag: "named"))
}

@Suite("Zerk interjections, named", sharedDoubles)
struct NamedZerkInterjectionsTests {

    @Test("a named set applies like an inline one")
    func namedApplies() {
        #expect((Zerk<Loading>.live as? TraitMock)?.tag == "named")
    }

    @Test("and is still per-test, not per-suite")
    func namedIsPerTest() {
        #Interject<Loading>(with: TraitMock(tag: "own"))
        #expect((Zerk<Loading>.live as? TraitMock)?.tag == "own")
    }
}

@Suite("Zerk interjections, named again", sharedDoubles)
struct NamedAgainZerkInterjectionsTests {

    @Test("the same set reaches a second suite untouched by the first")
    func reachesASecondSuite() {
        #expect((Zerk<Loading>.live as? TraitMock)?.tag == "named")
    }
}

struct TraitMock: Loading {
    let tag: String
    var source: String { tag }
}
