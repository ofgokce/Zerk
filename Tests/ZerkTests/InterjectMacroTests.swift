//
//  InterjectMacroTests.swift
//  Zerk
//

import Testing
import ZerkTesting
@testable import Zerk

// Real generated members back these: `Loading` has `live` and `seeded(source:)`,
// `SeededToken` has `seeded(seed:)`. See IntegrationFixtures.
//
// `.zerk` gives each test its own scope, which is how these are meant to be
// written — no `withInterjections` in sight. The primitive it rests on is
// covered separately in InterjectionStoreTests.
@Suite("#Interject", .zerk)
struct InterjectMacroTests {

    @Test("a blanket interjection covers every member of its key")
    func blanket() {
        #Interject<Loading>(with: MockLoading(tag: "blanket"))
        #expect((Zerk<Loading>.live as? MockLoading)?.tag == "blanket")
        #expect((Zerk<Loading>.seeded(source: "x") as? MockLoading)?.tag == "blanket")
    }

    @Test("the closure form builds the double lazily too")
    func blanketClosure() {
        #Interject<Loading> {
            let tag = "built"
            return MockLoading(tag: tag)
        }
        #expect((Zerk<Loading>.live as? MockLoading)?.tag == "built")
    }

    @Test("a key path stands in for exactly one member")
    func byKeyPath() {
        #Interject(\.live, with: MockLoading(tag: "just-live"))
        #expect((Zerk<Loading>.live as? MockLoading)?.tag == "just-live")
        // Untouched: still the real provider.
        #expect(Zerk<Loading>.seeded(source: "x") is MockLoading == false)
    }

    @Test("a parameterized member is reachable under its short name")
    func parameterizedByKeyPath() {
        // `seeded` is unique for SeededToken, so its point takes the bare name;
        // `Zerk<Loading>` has its own `seeded`, and the key path resolves against
        // the value's type.
        #Interject(\.seeded, with: SeededToken(value: 999))
        #expect(Zerk<SeededToken>.seeded(seed: 1).value == 999)
        #expect(SeededToken.factoryCount == 0)
    }

    @Test("an explicit key resolves a name shared by several keys")
    func explicitKeyDisambiguates() {
        #Interject<Loading>(\.live, with: MockLoading(tag: "explicit"))
        #expect((Zerk<Loading>.live as? MockLoading)?.tag == "explicit")
    }

    @Test("a key-path interjection beats a blanket over the same key")
    func precedence() {
        #Interject<Loading>(with: MockLoading(tag: "blanket"))
        #Interject(\.live, with: MockLoading(tag: "specific"))
        #expect((Zerk<Loading>.live as? MockLoading)?.tag == "specific")
        #expect((Zerk<Loading>.seeded(source: "x") as? MockLoading)?.tag == "blanket")
    }

    @Test("with: is re-evaluated per resolution, not captured once")
    func autoclosureIsLazy() {
        #Interject<Loading>(with: MockLoading(tag: "\(MockLoading.builds)"))
        let first = (Zerk<Loading>.live as? MockLoading)?.tag
        let second = (Zerk<Loading>.live as? MockLoading)?.tag
        #expect(first != second, "each resolution should rebuild the double")
    }

    @Test("interjections do not outlive their scope")
    func scoped() {
        #Interject<Loading>(with: MockLoading(tag: "inner"))
        #expect(Zerk<Loading>.live is MockLoading)
        // A nested scope of its own starts clean. Nothing here suspends, so this
        // takes the synchronous `withInterjections` overload — `await`ing the
        // async one warns that no async operation occurs within it.
        Zerk.withInterjections {
            #expect(Zerk<Loading>.live is MockLoading == false)
        }
    }
}

struct MockLoading: Loading {
    nonisolated(unsafe) static var builds = 0
    let tag: String
    var source: String { tag }
    init(tag: String) {
        self.tag = tag
        Self.builds += 1
    }
}
