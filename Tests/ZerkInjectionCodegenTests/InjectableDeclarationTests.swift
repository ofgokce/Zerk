//
//  InjectableDeclarationTests.swift
//  Zerk
//

import Testing
@testable import CodegenToolkit

/// Coverage of `@Injectable` on a global or static var/func, which registers the
/// type the declaration *produces* with the declaration as its provider.
///
/// This is how a type you cannot annotate joins the graph as a real key rather
/// than as a value matched by name. The key is the declared or returned type
/// unless a generic argument states one; the member takes the declaration's own
/// name unless `typeNamed:` or `name:` says otherwise.
@Suite("@Injectable declarations")
struct InjectableDeclarationTests {

    @Test("a global property registers its declared type")
    func globalPropertyRegistersItsType() throws {
        let source = """
        struct Session {}

        @Injectable
        var urlSession: Session { .init() }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("extension Zerk<Session> {"))
        #expect(result.output.output.contains("static var urlSession: Session {"))
        #expect(result.output.output.contains("static func inject() -> Session {"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("a global is reached through a thunk, not by its own name")
    func globalGoesThroughAThunk() throws {
        // Inside `extension Zerk<Session>` the unqualified `urlSession` resolves
        // to the member being defined, so reading it directly is infinite
        // recursion. A file-scope forwarding function breaks the cycle — the
        // same fix a referenced `@InjectableValue` uses.
        let source = """
        struct Session {}

        @Injectable
        var urlSession: Session { .init() }
        """

        let output = CompileFixture.generate(source: source)

        #expect(output.contains("private func _$zerk_provider_urlSession() -> Session { urlSession }"))
        #expect(output.contains("return _$zerk_provider_urlSession()"))
        // The recursive shape, which is what this exists to prevent.
        #expect(!output.contains("""
            static var urlSession: Session {
                    return urlSession
            """))
    }

    @Test("a static member is reached by its qualified path, with no thunk")
    func staticMemberNeedsNoThunk() throws {
        let source = """
        struct Session {}

        enum Container {
            @Injectable
            static var session: Session { .init() }
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("return Container.session"))
        #expect(!result.output.output.contains("_$zerk_provider"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("a written key registers that instead of the declared type")
    func writtenKeyWins() throws {
        let source = """
        protocol Sessioning {}
        struct Session: Sessioning {}

        @Injectable<Sessioning>
        var session: Session { .init() }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("extension Zerk<Sessioning> {"))
        #expect(result.output.output.contains("static var session: Sessioning {"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    // MARK: - Naming

    @Test("the member takes the declaration's name by default")
    func defaultNaming() {
        let output = CompileFixture.generate(source: """
        struct Session {}

        @Injectable
        var mySession: Session { .init() }
        """)

        #expect(output.contains("static var mySession: Session {"))
    }

    @Test("typeNamed: names it after the produced type")
    func typeNamedNaming() throws {
        let source = """
        struct Session {}

        @Injectable(typeNamed: true)
        var dummyName: Session { .init() }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("static var session: Session {"))
        #expect(!result.output.output.contains("static var dummyName"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("typeNamed: reads the declared type, not the key")
    func typeNamedReadsTheDeclaredType() {
        // `@Injectable<Sessioning>(typeNamed: true) var dummy: Session` is named
        // `session`, from what it produces — not `sessioning`, from the key.
        let output = CompileFixture.generate(source: """
        protocol Sessioning {}
        struct Session: Sessioning {}

        @Injectable<Sessioning>(typeNamed: true)
        var dummyName: Session { .init() }
        """)

        #expect(output.contains("static var session: Sessioning {"))
    }

    @Test("name: names the member outright")
    func explicitNaming() throws {
        let source = """
        struct Session {}

        @Injectable(name: "mainSession")
        var dummyName: Session { .init() }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("static var mainSession: Session {"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("stating both ways to name it is an error")
    func bothNamingsIsAnError() {
        let result = CompileFixture.generateWithResolution(source: """
        struct Session {}

        @Injectable(typeNamed: true, name: "mainSession")
        var dummyName: Session { .init() }
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error && $0.message.contains("name the same member two ways")
        })
    }

    // MARK: - Functions

    @Test("a function registers its return type and takes its parameters")
    func functionProvider() throws {
        let source = """
        struct Config {}
        struct Client {}

        @InjectableValues
        enum Values {
            static var config: Config { .init() }
        }

        @Injectable
        func makeClient(config: Config) -> Client { .init() }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        // The dependency resolves like any provider's.
        #expect(result.output.output.contains(
            "static func makeClient(config: Config = Zerk<Config>.config) -> Client {"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("a generic function registers exactly as a generic type would")
    func genericFunctionProvider() throws {
        let source = """
        struct Box<X, Y> {}

        @Injectable(typeNamed: true)
        func dummyName<X, Y>(x: X, y: Y) -> Box<X, Y> { .init() }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        // Key is the family; the member binds it per call.
        #expect(result.output.output.contains("extension Zerk {"))
        #expect(result.output.output.contains(
            "static func box<X, Y>(x: X, y: Y) -> Box<X, Y> where Injectable == Box<X, Y> {"))
        // The thunk carries the parameters through.
        #expect(result.output.output.contains(
            "private func _$zerk_provider_dummyName<X, Y>(x: X, y: Y) -> Box<X, Y> { dummyName(x: x, y: y) }"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    // MARK: - Placement

    @Test("an instance member is refused")
    func instanceMemberIsRefused() {
        // The generated file calls the declaration directly, and an instance
        // member has no reference it could call.
        let result = CompileFixture.generateWithResolution(source: """
        struct Session {}

        struct Container {
            @Injectable
            var session: Session { .init() }
        }
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error && $0.message.contains("needs it to be 'static'")
        })
    }

    @Test("a private declaration is refused")
    func privateDeclarationIsRefused() {
        // The generated file is a separate file in the same module.
        let result = CompileFixture.generateWithResolution(source: """
        struct Session {}

        @Injectable
        private var session: Session { .init() }
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error && $0.message.contains("at least internal")
        })
    }

    @Test("a function with no return type is refused")
    func voidFunctionIsRefused() {
        let result = CompileFixture.generateWithResolution(source: """
        @Injectable
        func doSomething() {}
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error && $0.message.contains("needs a return type")
        })
    }

    // MARK: - Interjection

    @Test("a declaration-backed key is interjectable like any other")
    func declarationKeyIsInterjectable() {
        let output = CompileFixture.generate(source: """
        struct Session {}

        @Injectable
        var urlSession: Session { .init() }
        """)

        #expect(output.contains("extension Zerk<Session>.Interjection"))
        #expect(output.contains("var `urlSession`: Void {}"))
        #expect(output.contains("if let interjected = _$interjected(for: \\.`urlSession`)"))
    }

    // MARK: - @Singleton

    @Test("a declaration may be a singleton")
    func declarationCanBeASingleton() throws {
        // Without this the marker was silently inert: the member called the
        // thunk on every resolution, so `@Singleton` bought a fresh instance
        // each time and said nothing about it.
        let source = """
        final class Session { init() {} }

        @Singleton
        @Injectable
        var urlSession: Session { Session() }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        // Stored once, built through the thunk. Storage is named after the
        // *produced type*, not the declaration — it is per type, which is what
        // lets every key claiming it read the same instance.
        #expect(result.output.output.contains(
            "nonisolated(unsafe) static let session: Session = _$zerk_provider_urlSession()"))
        // The lookup stays in the getter, so a double is consulted per read.
        #expect(result.output.output.contains("return _$zerk_singletons.session"))
        #expect(result.output.output.contains("if let interjected = _$interjected(for: \\.`urlSession`)"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("a static member declaration may be a singleton")
    func staticMemberCanBeASingleton() throws {
        let source = """
        final class Session { init() {} }

        enum Container {
            @Singleton
            @Injectable
            static var session: Session { Session() }
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        // A static member needs no thunk; storage calls it by its qualified path.
        #expect(result.output.output.contains(
            "nonisolated(unsafe) static let session: Session = Container.session"))
        #expect(!result.output.output.contains("_$zerk_provider"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("one instance is shared across every key the declaration claims")
    func singletonDeclarationIsSharedAcrossKeys() throws {
        let source = """
        protocol Sessioning: AnyObject {}
        protocol Caching: AnyObject {}
        final class Session: Sessioning, Caching { init() {} }

        @Singleton
        @Injectable<Sessioning>
        @Injectable<Caching>
        var session: Session { Session() }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        // One storage declaration, read by both keys' members.
        #expect(result.output.output.contains("static let session: Session ="))
        #expect(result.output.output.contains("extension Zerk<Sessioning>"))
        #expect(result.output.output.contains("extension Zerk<Caching>"))
        // And exactly one thunk, however many keys resolve through it.
        #expect(result.output.output.components(
            separatedBy: "private func _$zerk_provider_session").count - 1 == 1)

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("a singleton declaration keeps every other singleton constraint", arguments: [
        // An external argument cannot be supplied to storage built once.
        ("@Singleton\n@Injectable(typeNamed: true)\nfunc make(port: Int) -> Session { Session() }",
         "cannot accept external arguments"),
        // No static stored property exists to hold one per specialization.
        ("@Singleton\n@Injectable(typeNamed: true)\nfunc make<X>(x: X) -> Box<X> { Box() }",
         "@Singleton cannot be applied to the generic type"),
    ])
    ///
    /// The async constraint is deliberately absent: an effectful declaration is
    /// no longer refused, it moves into a `ZerkAsyncBox`. See
    /// ``asyncSingletonDeclarationIsKeptInABox``.
    func singletonConstraintsStillApply(source: String, message: String) {
        let result = CompileFixture.generateWithResolution(source: """
        final class Session { init() {} }
        final class Box<X> { init() {} }

        \(source)
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error && $0.message.contains(message)
        })
    }

    @Test("an async singleton declaration is kept in an async box")
    func asyncSingletonDeclarationIsKeptInABox() throws {
        let source = """
        final class Session: @unchecked Sendable { init() {} }

        @Singleton
        @Injectable
        var session: Session { get async { Session() } }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
        #expect(result.output.output.contains(
            "nonisolated static let session = ZerkAsyncBox<Session>()"))
        // A declaration is reached through its thunk here exactly as it is when
        // transient — the box changes where the value is kept, not how it is
        // built.
        #expect(result.output.output.contains(
            "return await _$zerk_singletons.session.value { await _$zerk_provider_session() }"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)\n\(compiled.generated)")
    }

    // MARK: - Isolation

    @Test("a declaration's isolation reaches its member and its thunk")
    func declarationIsolationIsMirrored() throws {
        // Without this the member said `nonisolated` while calling a
        // `@MainActor` global, which does not compile: "main actor-isolated var
        // 'session' can not be referenced from a nonisolated context".
        let source = """
        final class Session { init() {} }

        @MainActor
        @Injectable
        var session: Session { Session() }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("@MainActor static var session: Session {"))
        // The thunk calls the declaration directly, so it needs the isolation too.
        #expect(result.output.output.contains(
            "@MainActor private func _$zerk_provider_session() -> Session { session }"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("an isolated function declaration is mirrored too")
    func isolatedFunctionDeclaration() throws {
        let source = """
        final class Store { init() {} }

        @MainActor
        @Injectable(typeNamed: true)
        func makeStore() -> Store { Store() }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("@MainActor static var store: Store {"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("@Isolated states isolation the plugin cannot see")
    func isolatedMarkerOnADeclaration() {
        // A custom global actor whose name does not end in `Actor` is invisible
        // to the attribute heuristic — which is the case `@Isolated` exists for,
        // and it has to work here as it does on a type.
        let output = CompileFixture.generate(source: """
        final class Session { init() {} }

        @Isolated<DataStore>
        @DataStore
        @Injectable
        var session: Session { Session() }
        """)

        #expect(output.contains("@DataStore static var session: Session {"))
        #expect(output.contains("@DataStore private func _$zerk_provider_session()"))
    }

    @Test("@Isolated contradicting nonisolated is reported on a declaration")
    func contradictoryIsolationIsReported() {
        let result = CompileFixture.generateWithResolution(source: """
        final class Session { init() {} }

        @Isolated<DataStore>
        @Injectable
        nonisolated var session: Session { Session() }
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error
                && $0.message.contains("@Isolated<DataStore> contradicts the 'nonisolated' modifier")
        })
    }

    @Test("nonisolated opts a declaration out of the ambient default")
    func nonisolatedUnderAmbientMainActor() {
        var settings = ZerkSettings.default
        settings.defaultActorIsolation = .globalActor("MainActor")

        let output = CompileFixture.generate(source: """
        final class Session { init() {} }

        @Injectable
        nonisolated var session: Session { Session() }
        """, settings: settings)

        #expect(output.contains("nonisolated static var session: Session {"))
    }

    @Test("isolation and @Singleton combine on one declaration")
    func isolatedSingletonDeclaration() {
        // Global-actor isolation already protects the storage, so it gets no
        // `nonisolated(unsafe)` escape hatch.
        let output = CompileFixture.generate(source: """
        final class Cache { init() {} }

        @MainActor
        @Singleton
        @Injectable
        var cache: Cache { Cache() }
        """)

        #expect(output.contains("@MainActor static let cache: Cache = _$zerk_provider_cache()"))
        #expect(output.contains("@MainActor static var cache: Cache {"))
        #expect(!output.contains("nonisolated(unsafe) static let cache"))
    }
}
