//
//  InterjectionStoreTests.swift
//  Zerk
//

import Testing
@testable import Zerk

// Two keys a name-sanitizing scheme would have merged, and an alias group one
// could never have merged. Both are settled by metatype identity.
protocol IJServing: Sendable { var tag: String { get } }
protocol IJFooBar: Sendable {}
enum IJFoo { protocol Bar: Sendable {} }
typealias IJPersisting = IJServing

struct IJLive: IJServing { let tag = "live" }
struct IJMock: IJServing { let tag: String }

protocol IJOther: Sendable {}
struct IJOtherImpl: IJOther {}

// Interjection points, hand-written here exactly as the plugin will emit them:
// one per member, named with a raw identifier after that member's signature.

extension Zerk<any IJOther>.Interjection {
    var live: Void {}
}

extension Zerk<any IJServing>.Interjection {
    var live: Void {}
    var staging: Void {}
    var `seeded(seed: Int)`: Void {}
}

/// Stands in for a generated member: lookup first, real construction second.
///
/// No type annotation anywhere, which is the point of `_$interjected` returning
/// `T?` rather than a generic `V?`. An earlier generic version made
/// `_$interjected(…) ?? IJLive()` solve as the *fallback's* type instead of the
/// key, and every lookup then failed its cast.
private func member(_ keyPath: KeyPath<Zerk<any IJServing>.Interjection, Void>) -> any IJServing {
    if let interjected = Zerk<any IJServing>._$interjected(for: keyPath) { return interjected }
    return IJLive()
}

// Computed, not stored: `KeyPath` is not `Sendable`, so a global `let` of one is
// rejected under strict concurrency — typed or erased alike. Forming them at the
// use site, which is what a macro expansion does anyway, sidesteps it.
private var livePath: KeyPath<Zerk<any IJServing>.Interjection, Void> { \.live }
private var stagingPath: KeyPath<Zerk<any IJServing>.Interjection, Void> { \.staging }
private var seededPath: KeyPath<Zerk<any IJServing>.Interjection, Void> { \.`seeded(seed: Int)` }

private func fresh<R>(_ operation: () async throws -> R) async rethrows -> R {
    try await Zerk.withInterjections(operation)
}

@Suite("Interjection scope")
struct InterjectionScopeTests {

    @Test("no interjection resolves the real thing")
    func cleanScopeFallsThrough() async {
        await fresh {
            #expect(member(livePath).tag == "live")
        }
    }

    @Test("a key-path interjection stands in for exactly that member")
    func keyPathInterjection() async {
        await fresh {
            Zerk<any IJServing>._$interject(livePath) { IJMock(tag: "mock") }
            #expect(member(livePath).tag == "mock")
            #expect(member(stagingPath).tag == "live")
        }
    }

    @Test("a parameterized member is addressable by its signature")
    func parameterizedMemberIsAddressable() async {
        await fresh {
            Zerk<any IJServing>._$interject(seededPath) { IJMock(tag: "seeded") }
            #expect(member(seededPath).tag == "seeded")
            #expect(member(livePath).tag == "live")
        }
    }

    @Test("a blanket interjection covers every member, arguments included")
    func blanketInterjection() async {
        await fresh {
            Zerk<any IJServing>._$interject { IJMock(tag: "blanket") }
            #expect(member(livePath).tag == "blanket")
            #expect(member(seededPath).tag == "blanket")
        }
    }

    @Test("a key-path interjection beats a blanket")
    func precedence() async {
        await fresh {
            Zerk<any IJServing>._$interject { IJMock(tag: "blanket") }
            #expect(member(livePath).tag == "blanket")

            Zerk<any IJServing>._$interject(livePath) { IJMock(tag: "specific") }
            #expect(member(livePath).tag == "specific")
            #expect(member(stagingPath).tag == "blanket")
        }
    }

    @Test("interjections do not leak past their scope")
    func scopeUnwinds() async {
        await fresh {
            Zerk<any IJServing>._$interject { IJMock(tag: "inner") }
            #expect(member(livePath).tag == "inner")
        }
        await fresh {
            #expect(member(livePath).tag == "live")
        }
    }

    @Test("removeAll clears both dimensions, for XCTest")
    func removeAllClearsEverything() async {
        await fresh {
            Zerk<any IJServing>._$interject { IJMock(tag: "blanket") }
            Zerk<any IJServing>._$interject(livePath) { IJMock(tag: "specific") }
            ZerkInterjector.current.removeAll()
            #expect(member(livePath).tag == "live")
        }
    }

    // MARK: - Key identity

    @Test("keys that sanitize alike stay distinct")
    func punctuationDoesNotMergeKeys() {
        #expect(Zerk<any IJFooBar>._$interjectionKey != Zerk<any IJFoo.Bar>._$interjectionKey)
    }

    @Test("alias groups fold without the scope being told")
    func aliasesFold() {
        // A test target cannot know the module's @ZerkAlias declarations; the
        // metatype settles it, because the two names are one type.
        #expect(Zerk<any IJServing>._$interjectionKey == Zerk<any IJPersisting>._$interjectionKey)
        #expect(Zerk<[String]>._$interjectionKey == Zerk<Array<String>>._$interjectionKey)
    }

    @Test("different members get distinct key paths")
    func pathsAreDistinct() {
        #expect(livePath != stagingPath)
        #expect(livePath != seededPath)
    }

    @Test("a scope replaces the process default, which is what refuses leaks")
    func scopeReplacesTheProcessDefault() async {
        // The trap itself cannot be exercised — a precondition failure would
        // take the whole run down — so this checks the state that decides it.
        #expect(ZerkInterjector.isRunningInPreview == false)
        // No scope here, so the shared default is in force. Registering into it
        // is what would leak across concurrent tests, and what traps.
        #expect(ZerkInterjector.current === ZerkInterjector.processDefault)
        // Inside a scope it is an instance of this test's own, which accepts.
        await fresh {
            #expect(ZerkInterjector.current !== ZerkInterjector.processDefault)
        }
    }

    @Test("a key path infers its key, exactly as #Interject will")
    func inferenceMirrorsTheMacroSignature() {
        // The shape `#Interject(\.foo, with:)` expands from. Compiling at all is
        // the assertion: the key is solved from the key path alone, and `with:`
        // breaks the tie when a member name appears on more than one key —
        // `live` here exists on both IJServing and IJOther.
        func interject<T>(_ keyPath: KeyPath<Zerk<T>.Interjection, Void>,
                          with value: @autoclosure @escaping @Sendable () -> T) {}

        interject(\.`seeded(seed: Int)`, with: IJMock(tag: "unique name"))
        interject(\.live, with: IJMock(tag: "disambiguated by value"))
        interject(\.live, with: IJOtherImpl())
        #expect(Bool(true))
    }
}

// Separate suites so these genuinely run in parallel against each other.
@Suite("Interjection isolation A")
struct InterjectionIsolationA {
    @Test("sees only its own interjections")
    func isolated() async throws {
        try await Zerk.withInterjections {
            Zerk<any IJServing>._$interject { IJMock(tag: "A") }
            for _ in 0..<40 {
                #expect(member(livePath).tag == "A")
                try await Task.sleep(nanoseconds: 100_000)
            }
        }
    }
}

@Suite("Interjection isolation B")
struct InterjectionIsolationB {
    @Test("an untouched scope resolves the real thing throughout")
    func untouched() async throws {
        try await Zerk.withInterjections {
            for _ in 0..<40 {
                #expect(member(livePath).tag == "live")
                try await Task.sleep(nanoseconds: 100_000)
            }
        }
    }
}
