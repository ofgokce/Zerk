//
//  AutoInjectedTests.swift
//  Zerk
//

import Testing
@testable import CodegenToolkit

/// Coverage of `@autoinjected`, which turns a provider's inferred parameter
/// resolution into a stated one.
///
/// The default is inference: Zerk resolves whatever it can and leaves the rest
/// to the caller. That is convenient but silent — adding a type to the graph can
/// turn a caller-supplied parameter into a resolved one without anyone touching
/// the provider. Marking makes the choice explicit, and makes a mark Zerk cannot
/// honour a build error rather than a quiet fallback.
@Suite("@autoinjected")
struct AutoInjectedTests {

    /// Two injectable protocols and their implementations, for providers that
    /// need something to resolve.
    private static let graph = """
    protocol Storing {}
    protocol Logging {}

    @Injectable<Storing>
    final class FileStore: Storing {
        @InjectableProviding
        init() {}
    }

    @Injectable<Logging>
    final class Logger: Logging {
        @InjectableProviding
        init() {}
    }
    """

    // MARK: - Opt-in

    @Test("a provider with no marks keeps inferring")
    func unmarkedProviderInfers() {
        let source = """
        \(Self.graph)

        @Injectable
        final class Consumer {
            @InjectableProviding
            init(store: Storing, log: Logging) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        // Both resolved, so inject() needs nothing.
        #expect(result.output.output.contains("static func inject() -> Consumer"))
    }

    @Test("marking one parameter leaves the others to the caller")
    func markingOptsIntoExplicitMode() {
        let source = """
        \(Self.graph)

        @Injectable
        final class Consumer {
            @InjectableProviding
            init(@autoinjected store: Storing, log: Logging) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        // `log` is resolvable, but was not asked for.
        #expect(result.output.output.contains("static func inject(log: Logging) -> Consumer"))
        #expect(result.output.output.contains("store: Storing = Zerk<Storing>.inject()"))
    }

    @Test("an unmarked parameter stays external even when resolvable")
    func unmarkedParameterIsNeverResolved() {
        let source = """
        \(Self.graph)

        @Injectable
        final class Consumer {
            @InjectableProviding
            init(@autoinjected store: Storing, log: Logging) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        // The giveaway would be a default expression on `log`.
        #expect(!result.output.output.contains("log: Logging = Zerk<Logging>.inject()"))
    }

    @Test("explicit mode applies to an implicitly adopted initializer")
    func implicitInitializerHonoursMarks() {
        let source = """
        \(Self.graph)

        @Injectable
        final class Consumer {
            init(@autoinjected store: Storing, log: Logging) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("static func inject(log: Logging) -> Consumer"))
    }

    @Test("marks on a static factory work the same way")
    func staticFactoryHonoursMarks() {
        let source = """
        \(Self.graph)

        @Injectable
        final class Consumer {
            @InjectableProviding
            static func make(@autoinjected store: Storing, log: Logging) -> Consumer { Consumer() }

            init() {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("static func inject(log: Logging) -> Consumer"))
    }

    // MARK: - Diagnostics

    @Test("a mark Zerk cannot honour is an error at the parameter")
    func unresolvableMarkIsAnError() {
        let source = """
        protocol Storing {}

        @Injectable
        final class Consumer {
            @InjectableProviding
            init(
                label: String,
                @autoinjected store: Storing
            ) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        let failure = result.diagnostics.first {
            $0.severity == .error && $0.message.contains("@autoinjected parameter 'store'")
        }
        #expect(failure != nil)
        // Reported at the parameter, not at the initializer three lines above.
        #expect(failure?.location.line == 8)
    }

    @Test("the error is reported once for a provider serving several keys")
    func unresolvableMarkIsReportedOnce() {
        let source = """
        protocol Storing {}
        protocol A {}
        protocol B {}

        @Injectable<A, B>
        final class Consumer: A, B {
            @InjectableProviding
            init(@autoinjected store: Storing) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        let failures = result.diagnostics.filter {
            $0.message.contains("@autoinjected parameter 'store'")
        }
        #expect(failures.count == 1)
    }

    @Test("@autoinjected on a property is rejected")
    func markerOnPropertyIsRejected() {
        let source = """
        struct Consumer {
            @autoinjected
            var store: String = ""
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.contains {
            $0.severity == .error
                && $0.message.contains("@autoinjected is a provider-parameter marker")
        })
    }

    // MARK: - Inert marks

    @Test("a mark on a non-provider warns rather than failing", arguments: [
        // An initializer that is not the one carrying @InjectableProviding.
        """
        @Injectable
        final class Consumer {
            @InjectableProviding
            init(store: Storing) {}

            init(@autoinjected other: Storing, label: String) {}
        }
        """,
        // An ordinary method is never a provider.
        """
        @Injectable
        final class Consumer {
            @InjectableProviding
            init() {}

            func reload(@autoinjected store: Storing) {}
        }
        """,
        // A static factory that was never marked @InjectableProviding.
        """
        @Injectable
        final class Consumer {
            @InjectableProviding
            init() {}

            static func make(@autoinjected store: Storing) -> Consumer { Consumer() }
        }
        """,
        // The type is not injectable at all, so it has no provider.
        """
        final class Consumer {
            init(@autoinjected store: Storing) {}
        }
        """,
    ])
    func inertMarkWarns(_ declaration: String) {
        let result = CompileFixture.generateWithResolution(
            source: "\(Self.graph)\n\n\(declaration)"
        )

        let warnings = result.diagnostics.filter {
            $0.message.contains("@autoinjected has no effect here")
        }
        #expect(warnings.count == 1)
        #expect(warnings.first?.severity == .warning)
        // Inert, not wrong: the build still succeeds.
        #expect(!result.diagnostics.contains { $0.severity == .error })
    }

    @Test("the real provider does not warn")
    func providerDoesNotWarn() {
        let source = """
        \(Self.graph)

        @Injectable
        final class Consumer {
            @InjectableProviding
            init(@autoinjected store: Storing, label: String) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
    }

    @Test("an implicitly adopted initializer does not warn")
    func implicitProviderDoesNotWarn() {
        // No @InjectableProviding anywhere and a single initializer, so it is
        // the provider and the marks are live.
        let source = """
        \(Self.graph)

        @Injectable
        final class Consumer {
            init(@autoinjected store: Storing, label: String) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
    }

    // MARK: - Interaction

    @Test("a marked dependency that needs arguments bubbles them up")
    func markedDependencyBubblesItsArguments() {
        let source = """
        @Injectable
        final class Token {
            @InjectableProviding
            static func seeded(seed: Int) -> Token { Token() }

            init() {}
        }

        @Injectable
        final class Consumer {
            @InjectableProviding
            init(@autoinjected token: Token, label: String) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        // `label` is the provider's own and keeps its place; `seed` comes from
        // Token's provider and is appended after it.
        #expect(result.output.output.contains("static func inject(label: String, seed: Int) -> Consumer"))
    }

    @Test("@injected and @autoinjected compose")
    func markersCompose() throws {
        let source = """
        \(Self.graph)

        @Injectable
        final class Consumer {
            @InjectableProviding
            init(@injected @autoinjected store: Storing, label: String) {}
        }
        """

        let result = try CompileFixture.run(source: source)

        // @autoinjected drives the provider path...
        #expect(result.generated.contains("static func inject(label: String) -> Consumer"))
        // ...and @injected still generates the direct-construction overload.
        #expect(result.generated.contains("convenience init(label: String)"))

        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(result.didCompile, Comment(rawValue: result.compilerOutput))
    }

    @Test("marks survive the alias rewriting pass")
    func marksSurviveAliasRewriting() {
        // Regression: `AliasRewriter` used to rebuild each `ParameterRecord`
        // field by field, dropping the marker. It only showed up when a module
        // had aliases *and* marks, since the pass short-circuits when there are
        // none — so explicit mode silently reverted to inference.
        let source = """
        \(Self.graph)

        @ZerkAlias
        typealias Persisting = Storing

        @Injectable
        final class Consumer {
            @InjectableProviding
            init(@autoinjected store: Persisting, log: Logging) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("static func inject(log: Logging) -> Consumer"))
        #expect(!result.output.output.contains("log: Logging = Zerk<Logging>.inject()"))
    }

    @Test("a marked graph type-checks")
    func markedGraphCompiles() throws {
        let source = """
        \(Self.graph)

        @Injectable
        final class Consumer {
            @InjectableProviding
            init(@autoinjected store: Storing, log: Logging) {}
        }
        """

        let result = try CompileFixture.run(source: source)

        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(result.didCompile, Comment(rawValue: result.compilerOutput))
    }
}
