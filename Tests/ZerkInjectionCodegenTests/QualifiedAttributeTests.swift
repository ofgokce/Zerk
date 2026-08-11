//
//  QualifiedAttributeTests.swift
//  Zerk
//

import Testing
@testable import CodegenToolkit

/// A module-qualified attribute — `@Zerk.Injectable<Service>` — must mean
/// exactly what the unqualified spelling means.
///
/// `AttributeSyntax.name` has always accepted the qualified form, so the
/// attribute was recognised while its generic argument was dropped: the type
/// registered under *itself* instead of the key, with no diagnostic. Silent
/// wrong behaviour rather than a refusal, which is why it needs pinning at every
/// path that reads a key off an attribute.
@Suite("Module-qualified attributes")
struct QualifiedAttributeTests {

    // MARK: - The reader

    @Test("a qualified attribute yields its generic arguments")
    func readsGenericArgumentsWhenQualified() {
        // Both spellings, same answer. A test that only checked the qualified
        // one could pass against a reader that returned the wrong key.
        for source in ["@Zerk.Injectable<Service>", "@Injectable<Service>"] {
            let graph = CompileFixture.generate(source: """
            protocol Service {}

            \(source)
            struct Live: Service {
                @InjectableProviding
                init() {}
            }
            """)
            #expect(graph.contains("extension Zerk<Service> {"), "for \(source)")
            #expect(!graph.contains("extension Zerk<Live> {"), "for \(source)")
        }
    }

    @Test("several qualified keys on one type all register")
    func readsSeveralQualifiedKeys() {
        let output = CompileFixture.generate(source: """
        protocol Reading {}
        protocol Writing {}

        @Zerk.Injectable<Reading, Writing>
        struct Store: Reading, Writing {
            @InjectableProviding
            init() {}
        }
        """)

        #expect(output.contains("extension Zerk<Reading> {"))
        #expect(output.contains("extension Zerk<Writing> {"))
    }

    // MARK: - Every path that reads a key off an attribute

    @Test("a qualified @InjectableProviding binds the key it names")
    func qualifiedProvidingBindsItsKey() {
        let output = CompileFixture.generate(source: """
        protocol Reading {}
        protocol Writing {}

        @Injectable<Reading, Writing>
        struct Store: Reading, Writing {
            @Zerk.InjectableProviding<Reading>
            static func reader() -> Reading { Store() }

            @Zerk.InjectableProviding<Writing>
            static func writer() -> Writing { Store() }
        }
        """)

        // Bound to one key each. A dropped generic argument would make both
        // default providers, serving every key the type claims.
        #expect(output.contains("static var reader: Reading"))
        #expect(output.contains("static var writer: Writing"))
        #expect(!output.contains("static var reader: Writing"))
        #expect(!output.contains("static var writer: Reading"))
    }

    @Test("a qualified @Injected use is checked against the key it states")
    func qualifiedInjectedStatesItsKey() {
        // The stated key is deliberately *not* the property's declared type.
        // With them equal, dropping the generic argument falls back to the
        // declared type and produces the right answer by accident — which is
        // how this bug survived.
        let result = CompileFixture.generateWithResolution(source: """
        protocol Serving {}

        @Injectable<Serving>
        struct Live: Serving {
            @InjectableProviding
            static func make() async -> Serving { Live() }
        }

        @Injectable
        struct Plain {
            @InjectableProviding
            init() {}
        }

        struct Consumer {
            @Zerk.Injected<Serving> var service: Plain
        }
        """)

        // `Serving` has an async chain, so an @Injected against it is refused.
        // Reading the key as `Plain` instead would report nothing at all.
        let errors = result.diagnostics.filter { $0.severity == .error }
        #expect(errors.contains { $0.message.contains("'Serving'") })
    }

    @Test("a qualified @InjectableValue keys on what it says")
    func qualifiedValueKeysOnItsType() {
        let output = CompileFixture.generate(source: """
        @Zerk.InjectableValue
        var baseURL: String { "https://example.com" }
        """)

        #expect(output.contains("extension Zerk<String> {"))
    }
}
