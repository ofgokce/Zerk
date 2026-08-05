//
//  ZerkTraitTests.swift
//  Zerk
//

import Testing
import ZerkTesting
@testable import Zerk

/// The trait gives every test its own scope, so `#Interject` works with no
/// `withInterjections` in sight — and nothing leaks between tests.
@Suite("Zerk trait", .zerk)
struct ZerkTraitTests {

    @Test("a scope is in force without asking for one")
    func scopeIsProvided() {
        #expect(ZerkInterjections.current !== ZerkInterjections.processDefault)
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

/// The seeded form: every test starts from the same doubles, and may override.
@Suite("Zerk trait, seeded", .zerk { #Interject<Loading>(with: TraitMock(tag: "seed")) })
struct SeededZerkTraitTests {

    @Test("the seed is in force")
    func seedApplies() {
        #expect((Zerk<Loading>.live as? TraitMock)?.tag == "seed")
    }

    @Test("a test can override the seed")
    func testOverridesSeed() {
        #Interject<Loading>(with: TraitMock(tag: "own"))
        #expect((Zerk<Loading>.live as? TraitMock)?.tag == "own")
    }

    @Test("overriding in one test does not disturb another")
    func seedSurvivesElsewhere() async throws {
        for _ in 0..<40 {
            #expect((Zerk<Loading>.live as? TraitMock)?.tag == "seed")
            try await Task.sleep(nanoseconds: 100_000)
        }
    }
}

struct TraitMock: Loading {
    let tag: String
    var source: String { tag }
}
