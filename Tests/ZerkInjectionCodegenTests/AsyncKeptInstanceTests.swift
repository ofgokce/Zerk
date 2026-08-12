//
//  AsyncKeptInstanceTests.swift
//  Zerk
//

import Testing
@testable import CodegenToolkit

/// Coverage of `@Singleton` and `@Scoped` whose construction is `async` or
/// `throws`.
///
/// Both used to be refused, for two different storage reasons: a singleton's
/// `static let` initializer cannot await, and `ZerkScopedBox` builds under its
/// lock. `ZerkAsyncBox` replaces the storage for exactly the cases that need it,
/// so what is under test here is the *choice* — an effect-free kept instance
/// must keep its old, cheaper shape byte for byte.
///
/// The emitted text is checked with `swiftc` wherever an effect prefix is
/// involved: `await` on a call that does not suspend is a warning, not an
/// error, so a golden string alone would not notice one.
@Suite("Async kept instances")
struct AsyncKeptInstanceTests {

    static let scopeDeclarations = """
    extension InjectionScope {
        nonisolated static let session = InjectionScope("session")
    }
    """

    // MARK: - The storage choice

    @Test("an effect-free singleton keeps its plain static let")
    func synchronousSingletonIsUnchanged() {
        let generated = CompileFixture.generate(source: """
        @Singleton
        @Injectable
        final class Cache: @unchecked Sendable {}
        """)

        #expect(generated.contains(
            "nonisolated(unsafe) static let cache: Cache = Cache()"))
        #expect(!generated.contains("ZerkAsyncBox"))
        #expect(generated.contains("nonisolated static var cache: Cache {"))
    }

    @Test("an effect-free scoped instance keeps ZerkScopedBox")
    func synchronousScopedIsUnchanged() {
        let generated = CompileFixture.generate(source: """
        \(Self.scopeDeclarations)

        @Scoped(.session)
        @Injectable
        final class Session {}
        """)

        #expect(generated.contains(
            "nonisolated static let session = ZerkScopedBox<Session>(scope: .session)"))
        #expect(!generated.contains("ZerkAsyncBox"))
    }

    @Test("an async singleton moves into an async box")
    func asyncSingletonUsesAsyncBox() throws {
        let source = """
        @Singleton
        @Injectable
        final class Client: @unchecked Sendable {
            init() async {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
        // No `nonisolated(unsafe)`: the box is Sendable even where the instance
        // it holds needs the escape hatch.
        #expect(result.output.output.contains(
            "nonisolated static let client = ZerkAsyncBox<Client>()"))
        #expect(result.output.output.contains(
            "nonisolated static func client() async -> Client {"))
        #expect(result.output.output.contains(
            "return await _$zerk_singletons.client.value { await Client() }"))

        try expectCompiles(source)
    }

    @Test("an async scoped instance moves into an async box, keeping its scope")
    func asyncScopedUsesAsyncBox() throws {
        let source = """
        \(Self.scopeDeclarations)

        @Scoped(.session)
        @Injectable
        final class Session: @unchecked Sendable {
            init() async {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
        #expect(result.output.output.contains(
            "nonisolated static let session = ZerkAsyncBox<Session>(scope: .session)"))
        #expect(result.output.output.contains(
            "return await _$zerk_scoped.session.value { await Session() }"))

        try expectCompiles(source)
    }

    // MARK: - Effects on the read

    /// Building it throws; *reading* it is `async throws`, because joining the
    /// one build is what suspends. Worth its own test because the two effect
    /// sets are genuinely different, and only one of them appears in the source.
    @Test("a throwing kept instance reads as async throws")
    func throwingKeptInstanceReadsAsyncThrows() throws {
        let source = """
        @Singleton
        @Injectable
        final class Config: @unchecked Sendable {
            init() throws {}
        }
        """

        let generated = CompileFixture.generate(source: source)

        #expect(generated.contains(
            "nonisolated static func config() async throws -> Config {"))
        #expect(generated.contains(
            "return try await _$zerk_singletons.config.value { try Config() }"))
        #expect(generated.contains("nonisolated static func inject() async throws -> Config {"))

        try expectCompiles(source)
    }

    /// The inner prefix is the provider's own, never the merged effects: the
    /// dependency expressions carry their own `await`, and prefixing the whole
    /// construction again would put `await` on a call that does not suspend —
    /// which compiles, with a warning, and so needs the compiler to catch.
    @Test("a sync provider with an async dependency is not double-awaited")
    func syncProviderWithAsyncDependency() throws {
        let source = """
        protocol Loading: Sendable {}

        @Injectable<Loading>
        struct Loader: Loading {
            init() async {}
        }

        @Singleton
        @Injectable
        final class Cache: @unchecked Sendable {
            init(loading: Loading) {}
        }
        """

        let generated = CompileFixture.generate(source: source)

        #expect(generated.contains(
            "return await _$zerk_singletons.cache.value { Cache(loading: await Zerk<Loading>.inject()) }"))
        #expect(!generated.contains("value { await Cache("))

        try expectCompiles(source)
    }

    @Test("a kept instance may now depend on another isolation domain")
    func crossDomainDependencyIsAllowed() throws {
        let source = """
        @globalActor actor StoreActor { static let shared = StoreActor() }

        @StoreActor
        @Injectable
        final class Store: @unchecked Sendable {}

        @MainActor
        @Singleton
        @Injectable
        final class Cache: @unchecked Sendable {
            init(store: Store) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
        #expect(result.output.output.contains(
            "@MainActor static let cache = ZerkAsyncBox<Cache>()"))
        // `await` on the construction as well as on the dependency: the box's
        // closure is @Sendable, so it does not inherit the member's @MainActor
        // isolation and has to hop into it.
        #expect(result.output.output.contains(
            "return await _$zerk_singletons.cache.value { await Cache(store: await Zerk<Store>.inject()) }"))

        try expectCompiles(source)
    }

    // MARK: - What consumers see

    @Test("a consumer of an async kept instance resolves it asynchronously")
    func consumerResolvesAsynchronously() throws {
        let source = """
        protocol Connecting: Sendable {}

        @Singleton
        @Injectable<Connecting>
        final class Client: Connecting, @unchecked Sendable {
            init() async {}
        }

        @Injectable
        struct Screen {
            let connecting: Connecting
        }
        """

        let generated = CompileFixture.generate(source: source)

        // Not a default argument: `await` is illegal in one, so the dependency
        // is resolved in the body variant instead — the same split an async
        // transient already goes through.
        #expect(generated.contains("nonisolated static func screen() async -> Screen {"))
        #expect(generated.contains("screen(connecting: await Zerk<Connecting>.inject())"))

        try expectCompiles(source)
    }

    /// `@Injected` expands to a synchronous accessor, so it cannot resolve one —
    /// the existing refusal, which async kept instances now reach.
    @Test("@Injected refuses an async kept instance")
    func injectedRefusesAsyncKeptInstance() {
        let result = CompileFixture.generateWithResolution(source: """
        protocol Connecting: Sendable {}

        @Singleton
        @Injectable<Connecting>
        final class Client: Connecting, @unchecked Sendable {
            init() async {}
        }

        final class Screen {
            @Injected var connecting: Connecting
        }
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error
                && $0.message.contains("async, throwing, or cross-isolation dependency chain")
        }, "\(result.diagnostics.map(\.message))")
    }

    // MARK: - What is still refused

    @Test("an async kept instance still cannot take caller arguments")
    func externalArgumentsAreStillRefused() {
        let result = CompileFixture.generateWithResolution(source: """
        @Singleton
        @Injectable
        final class Client: @unchecked Sendable {
            init(port: Int) async {}
        }
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error
                && $0.message.contains("cannot accept external arguments")
        }, "\(result.diagnostics.map(\.message))")
    }

    /// `Task`'s result must be `Sendable`, so the box constrains its value. The
    /// plugin cannot see conformances, so this is the compiler's error to raise
    /// — the test's job is to prove it *is* raised rather than silently accepted.
    @Test("a non-Sendable async kept instance is rejected by the compiler")
    func nonSendableAsyncKeptInstanceFailsToCompile() throws {
        let result = try CompileFixture.run(source: """
        @Singleton
        @Injectable
        final class Client {
            var mutable = 0
            init() async {}
        }
        """)

        try #require(!result.skipped)
        #expect(!result.didCompile)
        #expect(result.compilerOutput.contains("Sendable"), Comment(rawValue: result.compilerOutput))
    }

    private func expectCompiles(_ source: String,
                                _ comment: Comment? = nil,
                                sourceLocation: SourceLocation = #_sourceLocation) throws {
        let result = try CompileFixture.run(source: source)
        try #require(!result.skipped, sourceLocation: sourceLocation)
        #expect(result.didCompile,
                comment ?? Comment(rawValue: "\(result.compilerOutput)\n\(result.generated)"),
                sourceLocation: sourceLocation)
    }
}
