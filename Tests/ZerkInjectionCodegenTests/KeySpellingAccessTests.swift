//
//  KeySpellingAccessTests.swift
//  Zerk
//

import Testing
@testable import CodegenToolkit

/// The two access guards, over every spelling a key can take.
///
/// Written as one parameterised suite on purpose. Both guards ask "is every type
/// this spelling mentions visible enough", and the answer was got wrong once per
/// spelling across four review passes — nested, then generic shape, then plain
/// specialization, then a specialization with a function-type argument, then a
/// composition — each fixed by a test naming that one input while its siblings
/// stayed uncovered.
///
/// The cause was a string scanner that counted `<` and `>` and mistook the `>` of
/// a `->` for the end of an argument list. The names now come from the syntax
/// tree, so the spellings below are one behaviour rather than six special cases —
/// and a seventh spelling is a row here, not another round.
@Suite("Key spellings and access")
struct KeySpellingAccessTests {

    /// A spelling, and what it should be judged on.
    struct Spelling {
        let name: String
        /// Declarations the fixture needs, with `Hidden` left internal.
        let declarations: String
        /// The key as written in the attribute.
        let key: String

        static let all: [Spelling] = [
            Spelling(name: "plain",
                     declarations: "protocol Hidden {}",
                     key: "any Hidden"),
            Spelling(name: "nested",
                     declarations: "public enum Outer { protocol Hidden {} }",
                     key: "any Outer.Hidden"),
            Spelling(name: "specialization",
                     declarations: "struct Hidden {}\npublic struct Box<E> {}",
                     key: "Box<Hidden>"),
            Spelling(name: "function-type argument",
                     declarations: "struct Hidden {}\npublic struct Box<E> {}",
                     key: "Box<(Hidden) -> Void>"),
            Spelling(name: "composition",
                     declarations: "public protocol Shown {}\nprotocol Hidden {}",
                     key: "any Shown & Hidden"),
            Spelling(name: "tuple",
                     declarations: "struct Hidden {}\npublic struct Shown {}",
                     key: "(Shown, Hidden)"),
            Spelling(name: "optional",
                     declarations: "protocol Hidden {}",
                     key: "(any Hidden)?"),
            Spelling(name: "array",
                     declarations: "protocol Hidden {}",
                     key: "[any Hidden]"),
        ]
    }

    /// `public: true` is refused whenever *any* type in the spelling is not
    /// public — a member exposing it is only as public as its least public part.
    @Test("public: true is inert when any part of the key is internal",
          arguments: Spelling.all)
    func exportIsRefusedForInternalComponents(spelling: Spelling) {
        let result = CompileFixture.generateWithResolution(source: """
        \(spelling.declarations)

        @Injectable<\(spelling.key)>(public: true)
        public struct Impl: Hidden {}
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .warning && $0.message.contains("has no effect")
        }, "\(spelling.name): \(result.diagnostics.map(\.message))")
        #expect(!result.output.output.contains("public static"),
                "\(spelling.name) emitted public members")
    }

    /// And honoured when every part is public, so the guard is not simply
    /// refusing everything.
    @Test("public: true is honoured when every part is public")
    func exportIsAllowedWhenEverythingIsPublic() {
        let result = CompileFixture.generateWithResolution(source: """
        public protocol Shown {}
        public protocol AlsoShown {}

        @Injectable<any Shown & AlsoShown>(public: true)
        public struct Impl: Shown, AlsoShown {}
        """)

        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
        #expect(result.output.output.contains("public static"))
    }

    /// The same question for the other guard: an `@injected` member in an
    /// extension of a type the generated file cannot see.
    @Test("an extension of an invisible type is refused, however it is spelled",
          arguments: [
            "Hidden",
            "Hidden<Int>",
            "Hidden<(Int) -> Void>",
            "Hidden<[String]>",
          ])
    func extensionVisibilityIsRefusedForEverySpelling(extended: String) {
        let generic = extended.contains("<") ? "<E>" : ""
        let result = CompileFixture.generateWithResolution(source: """
        protocol Repo {}

        @Injectable<Repo>
        struct RepoImpl: Repo {}

        fileprivate struct Hidden\(generic) {}

        extension \(extended) {
            func run(@injected repo: Repo, id: Int) -> Int { id }
        }
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error && $0.message.contains("'Hidden' is fileprivate")
        }, "\(extended): \(result.diagnostics.map(\.message))")
    }

    @Test("an extension of a visible type is not refused")
    func extensionVisibilityAllowsVisibleTypes() {
        let result = CompileFixture.generateWithResolution(source: """
        protocol Repo {}

        @Injectable<Repo>
        struct RepoImpl: Repo {}

        struct Shown<E> {}

        extension Shown<Int> {
            func run(@injected repo: Repo, id: Int) -> Int { id }
        }
        """)

        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
        #expect(result.output.output.contains("extension Shown<Int> {"))
    }

    @Test("an inferred factory key checks every nominal in the return type")
    func inferredFactoryKeyChecksEveryReturnNominal() {
        let result = CompileFixture.generateWithResolution(source: """
        struct Hidden {}
        public struct Box<E> {}

        @Injectable(public: true)
        public func makeBox() -> Box<Hidden> { fatalError() }
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .warning && $0.message.contains("has no effect")
        }, "\(result.diagnostics.map(\.message))")
        #expect(!result.output.output.contains("public static func makeBox"))
    }

    @Test("an alias-rewritten key checks the nominal types behind the alias")
    func aliasRewrittenKeyChecksUnderlyingNominals() {
        let result = CompileFixture.generateWithResolution(source: """
        struct Hidden {}
        public struct Box<E> {}

        @ZerkAlias
        typealias AliasBox = Box<Hidden>

        @Injectable<AliasBox>(public: true)
        public func makeAlias() -> AliasBox { fatalError() }
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .warning && $0.message.contains("has no effect")
        }, "\(result.diagnostics.map(\.message))")
        #expect(!result.output.output.contains("public static func makeAlias"))
    }

    @Test("declared access is judged inside the matching #if branch")
    func declaredAccessIsBranchAware() {
        let result = CompileFixture.generateWithResolution(source: """
        #if DEBUG
        public protocol Serving {}
        #else
        protocol Serving {}
        #endif

        #if DEBUG
        @Injectable<Serving>(public: true)
        public struct DebugService: Serving {}
        #else
        @Injectable<Serving>(public: true)
        struct ReleaseService: Serving {}
        #endif
        """)

        let warnings = result.diagnostics.filter {
            $0.severity == .warning && $0.message.contains("has no effect")
        }
        #expect(warnings.count == 1, "\(result.diagnostics.map(\.message))")
        #expect(result.output.output.contains("public static var debugService"))
        #expect(!result.output.output.contains("public static var releaseService"))
    }
}

extension KeySpellingAccessTests.Spelling: CustomTestStringConvertible {
    var testDescription: String { name }
}
