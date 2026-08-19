//
//  ZerkInterjectionsEdgeTests.swift
//  Zerk
//

import Testing
import ZerkTesting
@testable import Zerk

/// Parameterized and repeated tests — the shapes where a task-local trait is
/// most likely to hand two cases the same scope.
@Suite("Zerk interjections, edges", .zerk)
struct ZerkInterjectionsEdgeTests {

    @Test("each parameterized case gets its own scope", arguments: ["a", "b", "c", "d"])
    func parameterizedCasesAreIsolated(tag: String) async throws {
        #Interject<Loading>(with: EdgeMock(tag: tag))
        for _ in 0..<20 {
            #expect((Zerk<Loading>.live as? EdgeMock)?.tag == tag)
            try await Task.sleep(nanoseconds: 100_000)
        }
    }

    @Test("a repeated test starts clean each time", arguments: 0..<8)
    func repeatedRunsStartClean(_ run: Int) {
        // Nothing interjected yet: a scope carried over from a previous case
        // would show up right here.
        #expect(Zerk<Loading>.live is EdgeMock == false)
        #Interject<Loading>(with: EdgeMock(tag: "run-\(run)"))
        #expect((Zerk<Loading>.live as? EdgeMock)?.tag == "run-\(run)")
    }
}

struct EdgeMock: Loading {
    let tag: String
    var source: String { tag }
}
