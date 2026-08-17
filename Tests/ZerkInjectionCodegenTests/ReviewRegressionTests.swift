//
//  ReviewRegressionTests.swift
//  Zerk
//

import Testing
@testable import CodegenToolkit

/// One test per defect found reviewing the `#if` and async-kept-instance work.
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
    /// file the collector reached first. Widening to unconditional settled the
    /// order and cost the guard, which is worse — see
    /// `ConditionalCompilationTests.repeatedImportKeepsItsGuard`. Each guard now
    /// gets its own import, which is correct in every configuration *and* has no
    /// order to depend on.
    ///
    /// So the order axis stays, since that is what this test was written for,
    /// and is asserted directly: the two orderings must produce the same file,
    /// not merely the same claim about it.
    @Test("two guarded asks for one module are order-independent")
    func differingImportConditionsAreOrderIndependent() {
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
        let generated = CompileFixture.generate(source: "\(debug)\n\(ios)")
        let reversed = CompileFixture.generate(source: "\(ios)\n\(debug)")

        #expect(generated == reversed)
        #expect(generated.contains("#if (DEBUG)\nimport Mocks\n#endif"))
        #expect(generated.contains("#if (os(iOS))\nimport Mocks\n#endif"))
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

    /// An `@Injectable` function in an extension must be static too. Otherwise
    /// generation emits a static call to an instance member.
    @Test("an instance @Injectable function in an extension is refused")
    func instanceExtensionInjectableFunctionIsRefused() {
        let result = CompileFixture.generateWithResolution(source: """
        protocol Repo {}
        struct Service {}

        extension Service {
            @Injectable<Repo>
            func makeRepo() -> Repo { fatalError() }
        }
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error && $0.message.contains("needs it to be 'static'")
        }, "\(result.diagnostics.map(\.message))")
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

/// The fourth review pass: follow-on defects in generic shapes and extension keys.
@Suite("Review regressions, fourth pass")
struct ReviewRegressionsFourthPassTests {

    private static let repo = """
    protocol Repo {}

    @Injectable<Repo>
    struct RepoImpl: Repo {}
    """

    @Test("same-signature overloads in different constrained extensions do not collide")
    func sameSignatureConstrainedExtensionOverloadsDoNotCollide() throws {
        let source = """
        \(Self.repo)

        protocol Alpha {}
        protocol Beta {}

        struct Cache<E> {}

        extension Cache where E: Alpha {
            func run(@injected repo: Repo, item: E) -> E { item }
        }
        extension Cache where E: Beta {
            func run(@injected repo: Repo, item: E) -> E { item }
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
        #expect(result.output.output.contains("extension Cache where E: Alpha {"))
        #expect(result.output.output.contains("extension Cache where E: Beta {"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, Comment(rawValue: compiled.compilerOutput))
    }

    @Test("an extension of an invisible specialization is refused")
    func extensionOfInvisibleSpecializationIsRefused() {
        let result = CompileFixture.generateWithResolution(source: """
        \(Self.repo)

        fileprivate struct Hidden<E> {}

        extension Hidden<Int> {
            func run(@injected repo: Repo, id: Int) -> Int { id }
        }
        """)

        // Names the component that is actually hidden, and the extension it
        // was reached through.
        #expect(result.diagnostics.contains {
            $0.severity == .error
                && $0.message.contains("'Hidden' is fileprivate")
                && $0.message.contains("for 'Hidden<Int>'")
        }, "\(result.diagnostics.map(\.message))")
    }

    @Test("conditional referenced values emit one thunk per branch")
    func conditionalReferencedValueThunksCoverEachBranch() {
        let generated = CompileFixture.generate(source: """
        #if DEBUG
        @InjectableValue(.referenced)
        var baseURL: String = "debug"
        #else
        @InjectableValue(.referenced)
        var baseURL: String = "release"
        #endif
        """)

        #expect(generated.contains("#if (DEBUG)\nnonisolated private func _$zerk_ref_baseURL()"))
        #expect(generated.contains("#if !(DEBUG)\nnonisolated private func _$zerk_ref_baseURL()"))
    }

    @Test("conditional global providers emit one thunk per branch")
    func conditionalGlobalProviderThunksCoverEachBranch() {
        let generated = CompileFixture.generate(source: """
        protocol Service {}

        #if DEBUG
        struct DebugService: Service {}

        @Injectable<Service>
        func liveService() -> Service { DebugService() }
        #else
        struct ReleaseService: Service {}

        @Injectable<Service>
        func liveService() -> Service { ReleaseService() }
        #endif
        """)

        #expect(generated.contains("#if (DEBUG)\nnonisolated private func _$zerk_provider_liveService()"))
        #expect(generated.contains("#if !(DEBUG)\nnonisolated private func _$zerk_provider_liveService()"))
    }
}

/// The second review pass: defects in the fixes above, plus the extension path
/// the first pass introduced.
@Suite("Review regressions, second pass")
struct ReviewRegressionsSecondPassTests {

    private static func diagnostics(_ source: String) -> [CodegenDiagnostic] {
        CompileFixture.generateWithResolution(source: source).diagnostics
    }

    private static let repo = """
    protocol Repo {}

    @Injectable<Repo>
    struct RepoImpl: Repo {}
    """

    // MARK: - The refusal reaches extensions

    /// An `extension` pushes no type frame, so the refusal added for type bodies
    /// never ran there — leaving the very defect it was written for in the path
    /// the same commit introduced.
    @Test("a #if inside an extension is refused rather than dropped")
    func conditionalExtensionMemberIsRefused() {
        let diagnostics = Self.diagnostics("""
        \(Self.repo)

        struct Service {}

        extension Service {
            #if DEBUG
            func load(@injected repo: Repo, id: Int) -> Int { id }
            #endif
            func save(@injected repo: Repo, id: Int) -> Int { id }
        }
        """)

        #expect(diagnostics.contains {
            $0.severity == .error && $0.message.contains("is read differently per configuration")
        }, "\(diagnostics.map(\.message))")
    }

    // MARK: - The stored-property rule is only about required parameters

    /// Three shapes that compile and generate correctly, each refused by a check
    /// that flagged every conditional stored binding. The rule it protects —
    /// stated in Limitations.md — is about properties that would become
    /// *required* parameters.
    @Test("a conditional property that changes no parameter is allowed", arguments: [
        // Satisfied by its own macro, so not a parameter anywhere else either.
        """
        @Injectable
        final class Screen {
            #if DEBUG
            @Injected var dep: Dep
            #endif
            @InjectableProviding init() {}
        }
        """,
        // Defaulted, so the memberwise initializer does not ask for it.
        """
        @Injectable
        struct Config {
            let host: String
            #if DEBUG
            var verbose: Bool = false
            #endif
        }
        """,
        // An explicit provider means inference is never consulted at all.
        """
        @Injectable
        struct Config {
            let host: String
            #if DEBUG
            let verbose: Bool
            #endif
            @InjectableProviding init(host: String) { self.host = host }
        }
        """
    ])
    func harmlessConditionalPropertiesAreAllowed(source: String) {
        let diagnostics = Self.diagnostics("""
        protocol Dep {}

        @Injectable<Dep>
        struct DepImpl: Dep {}

        \(source)
        """)

        #expect(diagnostics.isEmpty, "\(diagnostics.map(\.message))")
    }

    @Test("a conditional property that *would* be a required parameter is refused")
    func requiredConditionalPropertyIsStillRefused() {
        let diagnostics = Self.diagnostics("""
        @Injectable
        struct Config {
            let host: String
            #if DEBUG
            let verbose: Bool
            #endif
        }
        """)

        #expect(diagnostics.contains {
            $0.severity == .error && $0.message.contains("is read differently per configuration")
        }, "\(diagnostics.map(\.message))")
    }

    // MARK: - What an extension knows about the type it extends

    /// An extension's own modifiers say nothing about the type it extends, so an
    /// unannotated extension of a `fileprivate` type read as `internal` and the
    /// generated overload could not see it.
    @Test("an extension of a type the generated file cannot see is refused")
    func extensionOfInvisibleTypeIsRefused() {
        let diagnostics = Self.diagnostics("""
        \(Self.repo)

        fileprivate struct Hidden {}

        extension Hidden {
            func run(@injected repo: Repo, id: Int) -> Int { id }
        }
        """)

        #expect(diagnostics.contains {
            $0.severity == .error && $0.message.contains("'Hidden' is fileprivate")
        }, "\(diagnostics.map(\.message))")
    }

    /// A `where` clause constrains an already-generic type; it is not what makes
    /// one generic. Reading it as genericness refused the *more* constrained
    /// extension while accepting the unconstrained one.
    @Test("a constrained extension of a generic type carries its where clause")
    func constrainedExtensionKeepsItsClause() {
        let result = CompileFixture.generateWithResolution(source: """
        \(Self.repo)

        struct Cache<E> {}

        extension Cache where E: Equatable {
            func run(@injected repo: Repo, item: E) -> E { item }
        }
        """)

        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
        // Without the clause the overload lands in an unconstrained extension
        // while its body calls a method that needs the constraint.
        #expect(result.output.output.contains("extension Cache where E: Equatable {"))
    }

    @Test("an unconstrained extension of a generic type still works")
    func unconstrainedGenericExtensionWorks() {
        let result = CompileFixture.generateWithResolution(source: """
        \(Self.repo)

        struct Cache<E> {}

        extension Cache {
            func run(@injected repo: Repo, item: E) -> E { item }
        }
        """)

        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
        #expect(result.output.output.contains("extension Cache {"))
    }
}

/// The third review pass: nested types and extension constraints, where the
/// same mistake — reading a *simple* name for something that has a qualified one
/// — had been made in three places at once.
@Suite("Review regressions, third pass")
struct ReviewRegressionsThirdPassTests {

    private static let repo = """
    protocol Repo {}

    @Injectable<Repo>
    struct RepoImpl: Repo {}
    """

    private static func generated(_ source: String) -> String {
        CompileFixture.generate(source: "\(Self.repo)\n\n\(source)")
    }

    private static func diagnostics(_ source: String) -> [CodegenDiagnostic] {
        CompileFixture.generateWithResolution(source: "\(Self.repo)\n\n\(source)").diagnostics
    }

    // MARK: - One extension block per constraint

    /// Grouping by type alone put every extension's members in one block under
    /// whichever `where` clause was collected first.
    @Test("two constrained extensions get two blocks")
    func constrainedExtensionsDoNotMerge() {
        let generated = Self.generated("""
        protocol Alpha {}
        protocol Beta {}

        struct Cache<E> {}

        extension Cache where E: Alpha {
            func a(@injected repo: Repo, item: E) -> E { item }
        }
        extension Cache where E: Beta {
            func b(@injected repo: Repo, item: E) -> E { item }
        }
        """)

        #expect(generated.contains("extension Cache where E: Alpha {"))
        #expect(generated.contains("extension Cache where E: Beta {"))
    }

    /// The worse half, because it compiled: an unconstrained member inherited
    /// the constraint and silently vanished for every other specialization.
    @Test("an unconstrained extension does not inherit a constraint")
    func unconstrainedExtensionKeepsItsFreedom() {
        let generated = Self.generated("""
        protocol Alpha {}

        struct Cache<E> {}

        extension Cache where E: Alpha {
            func constrained(@injected repo: Repo, item: E) -> E { item }
        }
        extension Cache {
            func plain(@injected repo: Repo, item: E) -> E { item }
        }
        """)

        // `plain` must be reachable for every E, so its block carries no clause.
        #expect(generated.contains("extension Cache {"))
        #expect(generated.contains("extension Cache where E: Alpha {"))
    }

    // MARK: - Qualified names

    /// `extensionStack` was added so a `#if` inside an extension is seen, but
    /// the qualified name still came from `typeStack` alone.
    @Test("a type declared inside an extension keeps its outer qualification")
    func nestedTypeInExtensionIsQualified() {
        let generated = Self.generated("""
        struct Outer {}

        extension Outer {
            struct Bar {
                func run(@injected repo: Repo, id: Int) -> Int { id }
            }
        }
        """)

        #expect(generated.contains("extension Outer.Bar {"))
        #expect(!generated.contains("extension Bar {"))
    }

    /// The visibility guard looked the type up by its simple name, so a nested
    /// one never matched and the check it was written for was skipped.
    @Test("a fileprivate nested type is refused")
    func fileprivateNestedTypeIsRefused() {
        let diagnostics = Self.diagnostics("""
        struct Outer { fileprivate struct Inner {} }

        extension Outer.Inner {
            func run(@injected repo: Repo, id: Int) -> Int { id }
        }
        """)

        #expect(diagnostics.contains {
            $0.severity == .error && $0.message.contains("'Outer.Inner' is fileprivate")
        }, "\(diagnostics.map(\.message))")
    }

    /// Same keying flaw, second map: `public: true` on a nested key emitted
    /// `public` unchecked, and the warning written for the case never fired.
    @Test("public: true on an internal nested key is reported, not emitted")
    func publicOnNestedInternalKeyIsInert() {
        let result = CompileFixture.generateWithResolution(source: """
        public struct Outer { struct Inner {} }

        @Injectable<Outer.Inner>(public: true)
        struct Impl {}
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .warning && $0.message.contains("has no effect")
        }, "\(result.diagnostics.map(\.message))")
        #expect(!result.output.output.contains("public static var impl"))
    }
}

/// The fifth pass: what a declaration's *location* means for the code Zerk
/// writes about it.
@Suite("Review regressions, fifth pass")
struct ReviewRegressionsFifthPassTests {

    private static func result(_ source: String) -> (output: GeneratorOutput, diagnostics: [CodegenDiagnostic]) {
        CompileFixture.generateWithResolution(source: source)
    }

    // MARK: - Nesting is refused rather than mis-emitted

    /// The key and the construction were both recorded as the declared name, so
    /// a nested registration emitted `Inner()` at file scope — "cannot find type
    /// 'Inner' in scope". Refused at the declaration instead.
    @Test("a nested @Injectable type is refused", arguments: [
        "struct Outer { @Injectable struct Inner { init() {} } }",
        "extension Outer { @Injectable struct Inner { init() {} } }",
    ])
    func nestedInjectableIsRefused(source: String) {
        let result = Self.result("""
        struct Outer {}

        \(source)
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error && $0.message.contains("declared inside 'Outer'")
        }, "\(result.diagnostics.map(\.message))")
        #expect(!result.output.output.contains("extension Zerk<Inner>"))
    }

    @Test("a top-level registration is unaffected")
    func topLevelRegistrationStillWorks() {
        let result = Self.result("@Injectable struct Top { init() {} }")

        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
        #expect(result.output.output.contains("extension Zerk<Top>"))
    }

    // MARK: - An extension member belongs to the type it extends

    /// `typeStack` is empty inside an extension, so the reference was built as
    /// though the declaration were global: a file-scope thunk calling a bare
    /// `make()` that exists nowhere.
    @Test("an @Injectable static func in an extension is reached through its type")
    func extensionProviderIsQualified() {
        let result = Self.result("""
        protocol Foo {}

        struct Service {}

        extension Service {
            @Injectable<Foo>
            static func make() -> Foo { fatalError() }
        }
        """)

        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
        #expect(result.output.output.contains("return Service.make()"))
        // No file-scope thunk: the qualified path is already unambiguous.
        #expect(!result.output.output.contains("_$zerk_provider_make"))
    }

    @Test("a referenced @InjectableValue in an extension is read through its type")
    func extensionValueIsQualified() {
        let result = Self.result("""
        struct Config {}

        struct Service {}

        extension Service {
            @InjectableValue(.referenced)
            static var config: Config { Config() }
        }
        """)

        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
        #expect(result.output.output.contains("return Service.config"))
        #expect(!result.output.output.contains("_$zerk_ref_config"))
    }

    // MARK: - What a `#if` in an extension may gate

    /// An extension holds no stored properties, so nothing there is inferred and
    /// a plain initializer is not read at all.
    @Test("a plain conditional initializer in an extension is allowed")
    func conditionalExtensionInitializerIsAllowed() {
        let result = Self.result("""
        struct Service { init() {} }

        extension Service {
            #if DEBUG
            init(debug: Bool) { self.init() }
            #endif
        }
        """)

        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
    }

    @Test("a conditional initializer carrying markers is still refused")
    func conditionalMarkedExtensionInitializerIsRefused() {
        let result = Self.result("""
        protocol Repo {}

        @Injectable<Repo>
        struct RepoImpl: Repo {}

        struct Service { init() {} }

        extension Service {
            #if DEBUG
            init(@injected repo: Repo) { self.init() }
            #endif
        }
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error && $0.message.contains("is read differently per configuration")
        }, "\(result.diagnostics.map(\.message))")
    }

    @Test("a conditional initializer in a type is still refused")
    func conditionalTypeInitializerIsRefused() {
        let result = Self.result("""
        @Injectable
        struct Service {
            #if DEBUG
            init(a: Int) {}
            #else
            init() {}
            #endif
        }
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error && $0.message.contains("is read differently per configuration")
        }, "\(result.diagnostics.map(\.message))")
    }
}

/// Housekeeping the reviews kept flagging: code nothing calls, a doc comment
/// attached to nothing, and a sort that could tie.
@Suite("Review housekeeping")
struct ReviewHousekeepingTests {

    /// A value registered under several keys is several records sharing a name,
    /// so ordering on the name alone left their order to `sorted`, which is not
    /// stable. The generated file is meant to be byte-identical between builds
    /// of identical source.
    @Test("a value under several keys emits in a deterministic order")
    func multiKeyValueOrderIsStable() {
        let source = """
        protocol Zed {}
        protocol Alpha {}

        struct Both: Zed, Alpha {}

        @InjectableValue<Zed, Alpha>
        var shared: Both { Both() }
        """

        let first = CompileFixture.generate(source: source)
        #expect(first == CompileFixture.generate(source: source))

        // Keyed after the name, so the two records order by key rather than by
        // whatever `sorted` happened to do with equal elements.
        let alpha = try? #require(first.range(of: "extension Zerk<Alpha> {"))
        let zed = try? #require(first.range(of: "extension Zerk<Zed> {"))
        if let alpha, let zed {
            #expect(alpha.lowerBound < zed.lowerBound)
        }
    }
}
