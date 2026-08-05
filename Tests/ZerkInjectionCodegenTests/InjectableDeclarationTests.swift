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
}
