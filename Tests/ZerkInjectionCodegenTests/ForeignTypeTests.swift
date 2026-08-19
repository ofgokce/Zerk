//
//  ForeignTypeTests.swift
//  Zerk
//

import Testing
@testable import CodegenToolkit

/// Coverage of registering a type you do not declare — `URLSession`, a type from
/// another module, anything out of reach of an annotation.
///
/// The key does not have to be the annotated declaration. `@Injectable<K>` on a
/// provider type says "these members build `K`", which is all the graph needs;
/// the declaration carrying it is just where the factory lives, and its own name
/// appears nowhere in resolution.
@Suite("Foreign types")
struct ForeignTypeTests {

    @Test("a provider type registers a key it is not")
    func providerTypeRegistersAForeignKey() throws {
        let source = """
        struct Session {}
        struct SessionConfig {}

        @Injectable<Session>
        enum SessionProvider {
            @InjectableProviding
            static func live(config: SessionConfig) -> Session { .init() }
        }

        @InjectableValues
        enum Config {
            static var config: SessionConfig { .init() }
        }

        @Injectable
        struct ApiClient {
            @InjectableProviding
            init(session: Session) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        // The key is `Session`; `SessionProvider` appears only as the callee.
        #expect(result.output.output.contains("extension Zerk<Session> {"))
        #expect(result.output.output.contains("return SessionProvider.live(config: config)"))
        #expect(!result.output.output.contains("extension Zerk<SessionProvider>"))
        // Full graph membership: the provider's own dependency resolves, and a
        // consumer resolves the foreign key like any other.
        #expect(result.output.output.contains("config: SessionConfig = Zerk<SessionConfig>.config"))
        #expect(result.output.output.contains("session: Session = Zerk<Session>.inject()"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("a foreign key is interjectable like any other")
    func foreignKeyIsInterjectable() {
        let source = """
        struct Session {}

        @Injectable<Session>
        enum SessionProvider {
            @InjectableProviding
            static func live() -> Session { .init() }
        }
        """

        let output = CompileFixture.generate(source: source)

        #expect(output.contains("extension Zerk<Session>.Interjection"))
        #expect(output.contains("if let interjected = _$interjected(for: \\.`live`)"))
    }

    @Test("@Injectable on an extension is refused, and says what to write")
    func extensionIsRefused() {
        // Not supported rather than not implemented: an extension states no
        // generic parameters of its own, so `extension Wrapper` cannot say
        // whether `Wrapper` is generic — and for a foreign type, which is the
        // whole point of the form, there is no way to find out.
        let source = """
        struct Session {}

        @Injectable
        extension Session {
            @InjectableProviding
            static func live() -> Session { .init() }
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.contains {
            $0.severity == .error
                && $0.message.contains("@Injectable cannot be applied to an extension")
                && $0.message.contains("@Injectable<Session> enum SessionProvider")
        })
        #expect(!result.output.output.contains("extension Zerk<Session> {"))
    }

    @Test("an injectable value inside an extension is still collected")
    func valuesInsideExtensionsStillWork() {
        // The extension visitor exists only to refuse `@Injectable`. It must
        // keep walking children, or every `@InjectableValue` written in an
        // extension would silently stop being collected.
        let source = """
        struct Config {}

        extension Config {
            @InjectableValue
            static var retryLimit: Int { 3 }
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("extension Zerk<Int> {"))
        #expect(result.output.output.contains("static var retryLimit: Int"))
    }
}
