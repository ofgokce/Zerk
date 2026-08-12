//
//  ReviewRegressionTests.swift
//  Zerk
//

import Testing
@testable import CodegenToolkit

/// One test per defect found reviewing the `#if`, async-kept-instance and
/// `--unused` work.
///
/// Grouped by what was wrong rather than by the file it was in, because that is
/// what a future change is likely to break again: each of these passed a full
/// suite before, and each was found by running the real tooling on a shape the
/// tests did not cover.
@Suite("Review regressions")
struct ReviewRegressionTests {

    // MARK: - Exclusivity is structural, never textual

    /// A pivot group took "everything compatible with *this* candidate", and an
    /// unconditional candidate is compatible with both clauses of one `#if` — so
    /// its group held a configuration no build ever has, and the fallback shape
    /// below could not be written at all.
    @Test("a fallback plus a per-configuration override resolves")
    func fallbackWithOverrideResolves() {
        let result = CompileFixture.generateWithResolution(source: """
        protocol Keying {}

        #if DEBUG
        @Injectable<Keying>(primary: true)
        struct DebugImpl: Keying {}
        #else
        @Injectable<Keying>(primary: true)
        struct ReleaseImpl: Keying {}
        #endif

        @Injectable<Keying>
        struct Fallback: Keying {}
        """)

        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
        // One per configuration, and the fallback is primary in neither.
        #expect(result.output.output.contains("#if (DEBUG)\n    nonisolated static func inject() -> Keying {\n        debugImpl\n    }"))
        #expect(result.output.output.contains("#if !(DEBUG)\n    nonisolated static func inject() -> Keying {\n        releaseImpl\n    }"))
    }

    @Test("a genuine ambiguity inside one configuration is still caught")
    func realAmbiguityStillCaught() {
        let result = CompileFixture.generateWithResolution(source: """
        protocol Keying {}

        #if DEBUG
        @Injectable<Keying>(primary: true)
        struct DebugImpl: Keying {}
        #endif

        @Injectable<Keying>(primary: true)
        struct AlwaysImpl: Keying {}
        """)

        // In a DEBUG build both exist and both are primary.
        #expect(result.diagnostics.contains {
            $0.message.contains("Multiple primary injectables")
        }, "\(result.diagnostics.map(\.message))")
    }

    /// Two guards can differ in text and still both hold — `#if DEBUG` and
    /// `#if os(macOS)` on a macOS debug build. Keying the overload check on the
    /// text let a real redeclaration through, replacing Zerk's error with the
    /// compiler's.
    @Test("overloads under non-exclusive guards still collide")
    func nonExclusiveOverloadsCollide() {
        let result = CompileFixture.generateWithResolution(source: """
        protocol Repo {}

        @Injectable<Repo>
        struct RepoImpl: Repo {}

        #if DEBUG
        func run(@injected repo: Repo, id: Int) -> Int { id }
        #endif
        #if os(macOS)
        func run(@injected repo: Repo, id: Int) -> Int { id }
        #endif
        """)

        #expect(result.diagnostics.contains {
            $0.message.contains("generate the same overload")
        }, "\(result.diagnostics.map(\.message))")
    }

    @Test("overloads under exclusive guards do not collide")
    func exclusiveOverloadsCoexist() {
        let result = CompileFixture.generateWithResolution(source: """
        protocol Repo {}

        @Injectable<Repo>
        struct RepoImpl: Repo {}

        #if DEBUG
        func run(@injected repo: Repo, id: Int) -> Int { id }
        #else
        func run(@injected repo: Repo, id: Int) -> Int { id }
        #endif
        """)

        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
    }

    // MARK: - What a `#if` inside a type may gate

    /// `inferredStructInitializer` reads the member list without descending into
    /// a `#if`, so a conditional stored property vanished from the parameters
    /// Zerk thought existed and it emitted a call missing an argument.
    @Test("a conditional stored property is refused")
    func conditionalStoredPropertyIsRefused() {
        let result = CompileFixture.generateWithResolution(source: """
        @Injectable
        struct Config {
            let host: String
            #if DEBUG
            let verbose: Bool
            #endif
        }
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error && $0.message.contains("is read differently per configuration")
        }, "\(result.diagnostics.map(\.message))")
    }

    /// A class only synthesizes `init()` when every stored property already has
    /// a value, so a *defaulted* conditional property changes nothing about how
    /// Zerk builds it.
    @Test("a defaulted conditional property in a class is allowed")
    func defaultedConditionalClassPropertyIsAllowed() {
        let result = CompileFixture.generateWithResolution(source: """
        @Injectable
        final class Cache {
            init() {}
            #if DEBUG
            var counter = 0
            #endif
        }
        """)

        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
    }

    /// The overload for an `@injected` member is assembled by walking the member
    /// list, which does not see inside a `#if` — so the member was dropped in
    /// silence and the call site failed later with a missing argument.
    @Test("a conditional @injected member is refused rather than dropped")
    func conditionalMarkedMemberIsRefused() {
        let result = CompileFixture.generateWithResolution(source: """
        protocol Repo {}

        @Injectable<Repo>
        struct RepoImpl: Repo {}

        struct Service {
            #if DEBUG
            func load(@injected repo: Repo, id: Int) -> Int { id }
            #endif
            func save(@injected repo: Repo, id: Int) -> Int { id }
        }
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error && $0.message.contains("is read differently per configuration")
        }, "\(result.diagnostics.map(\.message))")
    }

    @Test("a #if gating nothing Zerk reads is still allowed")
    func harmlessConditionalMembersAreAllowed() {
        let result = CompileFixture.generateWithResolution(source: """
        @Injectable
        struct Config {
            let host: String
            #if DEBUG
            func debugDump() {}
            var computed: Int { 0 }
            #endif
        }
        """)

        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
    }

    // MARK: - Imports

    /// Keeping the first condition meant the surviving one depended on which
    /// file the collector reached first, and a configuration that asked for the
    /// module did not get it.
    @Test("a module asked for under two conditions is imported unconditionally",
          arguments: [false, true])
    func differingImportConditionsWiden(reversed: Bool) {
        let debug = """
        #if DEBUG
        #ZerkImport(module: "Mocks")
        #endif
        """
        let ios = """
        #if os(iOS)
        #ZerkImport(module: "Mocks")
        #endif
        """
        let generated = CompileFixture.generate(
            source: reversed ? "\(ios)\n\(debug)" : "\(debug)\n\(ios)")

        #expect(generated.contains("import Mocks"))
        #expect(!generated.contains("#if (DEBUG)\nimport Mocks"))
        #expect(!generated.contains("#if (os(iOS))\nimport Mocks"))
    }

    @Test("a module asked for under one condition keeps its guard")
    func singleImportConditionIsKept() {
        let generated = CompileFixture.generate(source: """
        #if DEBUG
        #ZerkImport(module: "Mocks")
        #endif
        """)

        #expect(generated.contains("#if (DEBUG)\nimport Mocks\n#endif"))
    }

    // MARK: - `@injected` in an extension

    /// `isTopLevel` stopped at a code block but not at a member block, and an
    /// `extension` pushes no frame — so the method was treated as global and its
    /// overload landed at file scope, calling a method that is not there.
    @Test("an @injected extension method extends the type, not the file")
    func extensionMethodOverloadIsScoped() {
        let generated = CompileFixture.generate(source: """
        protocol Repo {}

        @Injectable<Repo>
        struct RepoImpl: Repo {}

        struct Service {}

        extension Service {
            func run(@injected repo: Repo, id: Int) -> Int { id }
        }
        """)

        #expect(generated.contains("extension Service {"))
        #expect(generated.contains("    nonisolated func run(id: Int) -> Int {"))
        // The broken shape: a file-scope function calling a method of a type it
        // is not inside.
        #expect(!generated.contains("\nnonisolated func run(id: Int)"))
    }

    /// Whether the generated overload needs `convenience` depends on whether the
    /// extended type is a class, which Zerk may never see.
    @Test("an @injected initializer in an extension is refused")
    func extensionInitializerIsRefused() {
        let result = CompileFixture.generateWithResolution(source: """
        protocol Repo {}

        @Injectable<Repo>
        struct RepoImpl: Repo {}

        struct Service {}

        extension Service {
            init(@injected repo: Repo) {}
        }
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error && $0.message.contains("declared in an extension")
        }, "\(result.diagnostics.map(\.message))")
    }

    @Test("a genuinely global @injected function is still global")
    func globalFunctionIsUnchanged() {
        let generated = CompileFixture.generate(source: """
        protocol Repo {}

        @Injectable<Repo>
        struct RepoImpl: Repo {}

        func run(@injected repo: Repo, id: Int) -> Int { id }
        """)

        #expect(generated.contains("\nnonisolated func run(id: Int) -> Int {"))
        // Every generated file extends `Zerk<Key>`; what must not appear is an
        // extension of some *other* type to hold the overload.
        let extended = generated
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.hasPrefix("extension ") && !$0.hasPrefix("extension Zerk") }
        #expect(extended.isEmpty, "\(extended)")
    }

    // MARK: - Rendering

    /// Widths were measured in `Character`s and applied with the `NSString`
    /// method, which counts UTF-16 — so a key with a combining sequence printed
    /// truncated and matched no declaration.
    @Test("a key whose UTF-16 length exceeds its character count is not truncated")
    func textPaddingDoesNotTruncate() {
        let combining = "Cafe\u{301}Service"
        #expect(combining.utf16.count > combining.count)

        let padded = GraphRenderer.padded(combining, to: combining.count + 3)
        #expect(padded.hasPrefix(combining))
        #expect(padded.count == combining.count + 3)
    }

    /// The escaper's entities are only interpreted inside a quoted string, so a
    /// bare title showed them verbatim — and a title needing no escaping could
    /// still break the parser on a space.
    @Test("a mermaid subgraph title is quoted")
    func mermaidSubgraphTitleIsQuoted() throws {
        let graph = ZerkPackageGraph(
            modules: [ZerkPackageGraph.Module(name: "My Module", keys: [], values: [])],
            imports: [],
            unresolvedImports: []
        )

        let mermaid = try GraphRenderer(graph: graph).render(.mermaid)
        #expect(mermaid.contains("subgraph cluster0[\"My Module\"]"))
    }
}
