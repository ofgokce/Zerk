//
//  InterjectionPointNameTests.swift
//  Zerk
//

import Testing
@testable import CodegenToolkit

/// Interjection points are named as short as the key allows, escalating only
/// where the shorter form would be ambiguous. Short names are what make
/// `#Interject(\.live, with: …)` bearable to write, so the escalation is worth
/// pinning in one place.
@Suite("Interjection point names")
struct InterjectionPointNameTests {

    private static let graph = """
    protocol Loading {}
    struct Disk {}
    struct Memory {}
    """

    @Test("a name used once takes the bare form")
    func uniqueNameIsBare() {
        let result = CompileFixture.generateWithResolution(source: """
        \(Self.graph)

        @Injectable<Loading>
        final class Solo: Loading {
            @InjectableProviding<Loading>
            static func solo(a: Int) -> Loading { Solo() }
            init() {}
        }
        """)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("var `solo`: Void {}"))
    }

    @Test("overloads differing by label take the selector form")
    func labelsDisambiguate() {
        let result = CompileFixture.generateWithResolution(source: """
        \(Self.graph)

        @Injectable<Loading>
        final class ByLabel: Loading {
            @InjectableProviding<Loading>(primary: true)
            static func loader(store: Disk) -> Loading { ByLabel() }
            @InjectableProviding<Loading>
            static func loader(cache: Memory) -> Loading { ByLabel() }
            init() {}
        }
        """)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("var `loader(store:)`: Void {}"))
        #expect(result.output.output.contains("var `loader(cache:)`: Void {}"))
        // The types are redundant here, so the point stays in selector form —
        // checked against the point, since the member's own declaration spells
        // `loader(store: Disk)` regardless.
        #expect(!result.output.output.contains("var `loader(store: Disk)`"))
    }

    @Test("overloads differing only by type take the full form")
    func typesDisambiguate() {
        let result = CompileFixture.generateWithResolution(source: """
        \(Self.graph)

        @Injectable<Loading>
        final class ByType: Loading {
            @InjectableProviding<Loading>(primary: true)
            static func picker(store: Disk) -> Loading { ByType() }
            @InjectableProviding<Loading>
            static func picker(store: Memory) -> Loading { ByType() }
            init() {}
        }
        """)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("var `picker(store: Disk)`: Void {}"))
        #expect(result.output.output.contains("var `picker(store: Memory)`: Void {}"))
    }

    @Test("a group escalates as a whole, never a mix of forms")
    func escalationIsPerGroup() {
        // Three overloads: two share `store:`, so labels cannot separate the
        // group and every member of it takes the full form — including the one
        // whose label was already unique.
        let result = CompileFixture.generateWithResolution(source: """
        \(Self.graph)

        @Injectable<Loading>
        final class Mixed: Loading {
            @InjectableProviding<Loading>(primary: true)
            static func pick(store: Disk) -> Loading { Mixed() }
            @InjectableProviding<Loading>
            static func pick(store: Memory) -> Loading { Mixed() }
            @InjectableProviding<Loading>
            static func pick(cache: Disk) -> Loading { Mixed() }
            init() {}
        }
        """)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("var `pick(store: Disk)`: Void {}"))
        #expect(result.output.output.contains("var `pick(store: Memory)`: Void {}"))
        #expect(result.output.output.contains("var `pick(cache: Disk)`: Void {}"))
        #expect(!result.output.output.contains("var `pick(cache:)`: Void {}"))
    }
}
