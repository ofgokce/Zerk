//
//  InjectableProvidingNamingTests.swift
//  Zerk
//

import Testing
@testable import CodegenToolkit

/// Coverage of `@InjectableProviding(typeNamed:)` and `@InjectableProviding(name:)`,
/// which name the member a provider generates.
///
/// The defaults are what the declaration gives: a factory's member takes the
/// factory's name, an initializer's takes its type's. Both are right while the
/// provider lives with the thing it builds, and wrong once it does not — a
/// provider type exists to build something that is not itself, so its factory's
/// name says nothing about the key.
@Suite("@InjectableProviding naming")
struct InjectableProvidingNamingTests {

    // MARK: - Defaults

    @Test("a factory keeps its own name")
    func factoryKeepsItsName() {
        let output = CompileFixture.generate(source: """
        protocol Loading {}

        @Injectable<Loading>
        struct Loader: Loading {
            @InjectableProviding
            static func live() -> Loading { Loader() }
        }
        """)

        #expect(output.contains("static var live: Loading {"))
    }

    @Test("an initializer's member is named after its type")
    func initializerTakesItsTypeName() {
        let output = CompileFixture.generate(source: """
        protocol Loading {}

        @Injectable<Loading>
        struct Loader: Loading {
            @InjectableProviding
            init() {}
        }
        """)

        #expect(output.contains("static var loader: Loading {"))
    }

    // MARK: - typeNamed:

    @Test("typeNamed: names a factory's member after the type it returns")
    func typeNamedUsesTheReturnType() throws {
        // The case the argument exists for: `SessionProvider` is not the thing
        // being built, so neither its name nor `live` describes the member.
        let source = """
        struct Session {}

        @Injectable<Session>
        enum SessionProvider {
            @InjectableProviding(typeNamed: true)
            static func live() -> Session { .init() }
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("static var session: Session {"))
        #expect(result.output.output.contains("return SessionProvider.live()"))
        #expect(!result.output.output.contains("static var live"))
        // Not the enclosing type, which is what the emitter's own fallback
        // would have given.
        #expect(!result.output.output.contains("sessionProvider"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("typeNamed: reads the return type, not the key")
    func typeNamedReadsTheReturnTypeNotTheKey() throws {
        // `Zerk<Sessioning>.session`, from what the factory returns — not
        // `.sessioning`, from the key it is registered under. The member's
        // *type* is still the key.
        let source = """
        protocol Sessioning {}
        struct Session: Sessioning {}

        @Injectable<Sessioning>
        enum SessionProvider {
            @InjectableProviding(typeNamed: true)
            static func live() -> Session { .init() }
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("extension Zerk<Sessioning> {"))
        #expect(result.output.output.contains("static var session: Sessioning {"))
        #expect(!result.output.output.contains("sessioning:"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("a generic factory is named after its return type's base")
    func genericFactoryTypeNamed() throws {
        let source = """
        @Injectable
        struct Box<X, Y> {
            init(x: X, y: Y) {}

            @InjectableProviding(typeNamed: true)
            static func make(x: X, y: Y) -> Box<X, Y> { .init(x: x, y: y) }
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains(
            "static func box<X, Y>(x: X, y: Y) -> Box<X, Y> where Injectable == Box<X, Y> {"))
        #expect(!result.output.output.contains("static func make<"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    // MARK: - name:

    @Test("name: names a factory's member outright")
    func explicitNameOnAFactory() throws {
        let source = """
        struct Session {}

        @Injectable<Session>
        enum SessionProvider {
            @InjectableProviding(name: "mainSession")
            static func live() -> Session { .init() }
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("static var mainSession: Session {"))
        #expect(!result.output.output.contains("static var live"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("name: renames an initializer's member too")
    func explicitNameOnAnInitializer() throws {
        // The one naming argument an initializer takes, and the only way to
        // move it off its type's name.
        let source = """
        protocol Loading {}

        @Injectable<Loading>
        struct Loader: Loading {
            @InjectableProviding(name: "live")
            init() {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("static var live: Loading {"))
        #expect(!result.output.output.contains("static var loader"))
        #expect(result.output.output.contains("return Loader()"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("a renamed provider still backs inject() when it is primary")
    func renamedPrimaryStillBacksInject() throws {
        let source = """
        protocol Loading {}

        @Injectable<Loading>
        struct Loader: Loading {
            @InjectableProviding(name: "live", primary: true)
            static func make() -> Loading { Loader() }

            @InjectableProviding
            static func cached() -> Loading { Loader() }
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("static var live: Loading {"))
        #expect(result.output.output.contains("static var cached: Loading {"))
        // inject() calls the member, so the rename has to reach it — while the
        // construction still calls the factory by its real name.
        #expect(result.output.output.contains("""
            static func inject() -> Loading {
                    live
            """))
        #expect(result.output.output.contains("return Loader.make()"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("naming is per attribute, as primary is")
    func namingIsPerAttribute() throws {
        // One factory bound to two keys, named differently under each. The
        // records are per attribute already, because `primary:` is a claim
        // about a single key; naming rides the same split.
        let source = """
        protocol Loading {}
        protocol Caching {}
        struct Store: Loading, Caching {}

        @Injectable<Loading>
        @Injectable<Caching>
        enum StoreProvider {
            @InjectableProviding<Loading>(name: "live")
            @InjectableProviding<Caching>(typeNamed: true)
            static func make() -> Store { .init() }
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("static var live: Loading {"))
        #expect(result.output.output.contains("static var store: Caching {"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    // MARK: - Interjection

    @Test("the interjection point follows the renamed member")
    func interjectionPointFollowsTheName() {
        let output = CompileFixture.generate(source: """
        struct Session {}

        @Injectable<Session>
        enum SessionProvider {
            @InjectableProviding(typeNamed: true)
            static func live() -> Session { .init() }
        }
        """)

        #expect(output.contains("var `session`: Void {}"))
        #expect(output.contains("if let interjected = _$interjected(for: \\.`session`)"))
        #expect(!output.contains("`live`"))
    }

    // MARK: - Refusals

    @Test("typeNamed: on an initializer is refused, and says what to write")
    func typeNamedOnInitializerIsRefused() {
        // It could only ever be a no-op: an initializer produces its own type,
        // which its member is named after already.
        let result = CompileFixture.generateWithResolution(source: """
        protocol Loading {}

        @Injectable<Loading>
        struct Loader: Loading {
            @InjectableProviding(typeNamed: true)
            init() {}
        }
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error
                && $0.message.contains("does not apply to an initializer")
                && $0.message.contains("Write 'name:'")
        })
    }

    @Test("typeNamed: needs a return type with a name to lend")
    func typeNamedNeedsANamedReturnType() {
        let result = CompileFixture.generateWithResolution(source: """
        protocol Pairing {}

        @Injectable<Pairing>
        enum PairProvider {
            @InjectableProviding(typeNamed: true)
            static func live() -> (Int, String) { (0, "") }
        }
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error
                && $0.message.contains("@InjectableProviding(typeNamed:)")
                && $0.message.contains("none to lend")
        })
    }

    @Test("stating both ways to name it is an error")
    func bothNamingsIsAnError() {
        let result = CompileFixture.generateWithResolution(source: """
        struct Session {}

        @Injectable<Session>
        enum SessionProvider {
            @InjectableProviding(typeNamed: true, name: "mainSession")
            static func live() -> Session { .init() }
        }
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error
                && $0.message.contains("@InjectableProviding states both")
                && $0.message.contains("name the same member two ways")
        })
    }

    @Test("a non-literal name is refused")
    func nonLiteralNameIsRefused() {
        let result = CompileFixture.generateWithResolution(source: """
        struct Session {}
        let chosenName = "mainSession"

        @Injectable<Session>
        enum SessionProvider {
            @InjectableProviding(name: chosenName)
            static func live() -> Session { .init() }
        }
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error
                && $0.message.contains("@InjectableProviding(name:) requires a string literal")
        })
    }

    @Test("a non-literal typeNamed: is refused")
    func nonLiteralTypeNamedIsRefused() {
        let result = CompileFixture.generateWithResolution(source: """
        struct Session {}
        let useTypeName = true

        @Injectable<Session>
        enum SessionProvider {
            @InjectableProviding(typeNamed: useTypeName)
            static func live() -> Session { .init() }
        }
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error
                && $0.message.contains("@InjectableProviding(typeNamed:) requires a 'true' or 'false' literal")
        })
    }

    @Test("a rename that collides with a sibling is reported")
    func renameCollisionIsReported() {
        // Two factories told apart by their own names are not told apart once
        // both are named after what they return.
        let result = CompileFixture.generateWithResolution(source: """
        struct Session {}

        @Injectable<Session>
        enum SessionProvider {
            @InjectableProviding(typeNamed: true, primary: true)
            static func live() -> Session { .init() }

            @InjectableProviding(typeNamed: true)
            static func mock() -> Session { .init() }
        }
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error && $0.message.contains("collides")
        })
    }

    // MARK: - Diagnostics name the declaration

    @Test("a generic refusal names the factory, not the member it would generate")
    func diagnosticsNameTheDeclaration() {
        // The member's name is the one thing that does not appear in the source
        // being complained about, so a rename must not reach the message.
        let result = CompileFixture.generateWithResolution(source: """
        protocol Storing {}
        struct Store<E>: Storing {}

        @Injectable<Storing>
        enum StoreProvider {
            @InjectableProviding(name: "live")
            static func make<E>() -> Store<E> { .init() }
        }
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error && $0.message.contains("'make'")
        })
        #expect(!result.diagnostics.contains { $0.message.contains("'live'") })
    }
}

/// A produced type that is nested, which is the only way a type *name* reaches
/// member naming with a dot in it.
@Suite("Nested produced types")
struct NestedProducedTypeNamingTests {

    @Test("a nested return type lends only its last component")
    func nestedReturnTypeNaming() throws {
        let source = """
        enum Keychain {
            struct Store {}
        }

        @Injectable<Keychain.Store>
        enum StoreProvider {
            @InjectableProviding(typeNamed: true)
            static func live() -> Keychain.Store { .init() }
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        // `keychain.Store` is not an identifier, so the qualification drops.
        #expect(result.output.output.contains("static var store: Keychain.Store {"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("a nested declared type lends only its last component")
    func nestedDeclaredTypeNaming() throws {
        let source = """
        enum Keychain {
            struct Store {}
        }

        @Injectable(typeNamed: true)
        var dummyName: Keychain.Store { .init() }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("static var store: Keychain.Store {"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }
}
