//
//  GenericScopeTests.swift
//  Zerk
//

import Testing
import SwiftParser
import SwiftSyntax
@testable import CodegenToolkit
import SharedToolkit

/// Coverage of the reading layer for generics: which generic parameters a type
/// mentions, and how the collector knows which are in scope where.
///
/// Nothing here is emitted yet — `GenericGate` still refuses every generic
/// registration. What is under test is that the records are *right*, so that
/// matching and emission can be built on them rather than on a re-read.
///
/// The analysis is a syntax walk, and the cases below are the reason: every
/// plausible string test gets one of them wrong.
@Suite("Generic scope")
struct GenericScopeTests {

    /// Parses a spelling into the exact node shape a real provider parameter
    /// has, rather than building one — sugar, function types and compositions
    /// all parse differently from how they would be assembled.
    private static func type(_ text: String) -> TypeSyntax {
        let file = Parser.parse(source: "func _probe(_ x: \(text)) {}")
        let parameter = file.statements.first?.item.as(FunctionDeclSyntax.self)?
            .signature.parameterClause.parameters.first
        return parameter!.type
    }

    // MARK: - Which parameters a type mentions

    @Test("a type mentions the parameters it actually names", arguments: [
        ("E", ["E"]),
        ("Serializer<E>", ["E"]),
        ("Array<E>", ["E"]),
        ("[E]", ["E"]),
        ("[String: E]", ["E"]),
        ("E?", ["E"]),
        ("Cache<Cache<E>>", ["E"]),
        ("(E) -> Int", ["E"]),
        ("(Int) -> E", ["E"]),
        ("(E, F)", ["E", "F"]),
        ("any Caching<E>", ["E"]),
        ("E.Element", ["E"]),
        ("Logger", []),
    ])
    func mentions(_ written: String, _ expected: [String]) {
        #expect(Self.type(written).mentionedGenericParameters(in: ["E", "F"]) == expected)
    }

    @Test("a name that merely looks like a parameter is not one", arguments: [
        "Encoder",      // starts with E
        "Serializer<Element>",  // contains E, and Element starts with E
        "Foo.E",        // a nested type of Foo, not the parameter
        "EE",
    ])
    func lookalikesAreNotMentions(_ written: String) {
        #expect(Self.type(written).mentionedGenericParameters(in: ["E"]).isEmpty)
    }

    @Test("mentions come back in source order, without repeats")
    func mentionsAreOrderedAndUnique() {
        let written = Self.type("Pair<F, Dictionary<E, F>>")
        #expect(written.mentionedGenericParameters(in: ["E", "F"]) == ["F", "E"])
    }

    @Test("an empty scope mentions nothing, whatever the type")
    func emptyScopeMentionsNothing() {
        #expect(Self.type("Serializer<E>").mentionedGenericParameters(in: []).isEmpty)
        #expect(Self.type("E").isBareGenericParameter(in: []) == false)
    }

    // MARK: - Bare parameters

    @Test("a bare parameter is told apart from a type mentioning one", arguments: [
        ("E", true),
        ("(E)", true),        // grouping, not a one-element tuple
        ("E?", false),
        ("Serializer<E>", false),
        ("E.Element", false),
        ("Logger", false),
    ])
    func bareParameters(_ written: String, _ expected: Bool) {
        #expect(Self.type(written).isBareGenericParameter(in: ["E"]) == expected)
    }

    // MARK: - What the collector records

    private static func collect(_ source: String) -> SourceCollector {
        let collector = SourceCollector()
        collector.walk(Parser.parse(source: source))
        return collector
    }

    @Test("a generic type records its own parameters, in order")
    func typeRecordsItsParameters() throws {
        let collector = Self.collect("""
        @Injectable
        struct Store<K, V> {
            @InjectableProviding
            init() {}
        }
        """)

        let record = try #require(collector.types.first)
        #expect(record.name == "Store")
        #expect(record.genericParameters == ["K", "V"])
    }

    @Test("a provider parameter records which parameters its type mentions")
    func providerParametersRecordTheirMentions() throws {
        let collector = Self.collect("""
        @Injectable
        struct Cache<E> {
            @InjectableProviding
            init(logger: Logger, serializer: Serializer<E>, item: E) {}
        }
        """)

        let parameters = try #require(collector.types.first?.initializers.first?.parameters)
        #expect(parameters.count == 3)

        // Concrete: one key, resolvable by exact match.
        #expect(parameters[0].mentionedGenericParameters.isEmpty)
        #expect(parameters[0].isBareGenericParameter == false)

        // A family of keys.
        #expect(parameters[1].mentionedGenericParameters == ["E"])
        #expect(parameters[1].isBareGenericParameter == false)

        // Neither — nothing registers `E`.
        #expect(parameters[2].mentionedGenericParameters == ["E"])
        #expect(parameters[2].isBareGenericParameter)
    }

    @Test("a static factory's parameters are read in the same scope")
    func staticFactoryParametersShareTheScope() throws {
        // The factory itself is non-generic; the scope comes from the type.
        let collector = Self.collect("""
        @Injectable
        struct Cache<E> {
            @InjectableProviding
            static func live(serializer: Serializer<E>) -> Cache { .init() }
            init() {}
        }
        """)

        let providers = try #require(collector.types.first?.defaultProviders)
        let parameters = try #require(providers.first?.parameters)
        #expect(parameters.first?.mentionedGenericParameters == ["E"])
    }

    @Test("the synthesized memberwise initializer is read in the same scope")
    func synthesizedMemberwiseInitializerSharesTheScope() throws {
        // This path builds its records by hand rather than through the
        // parameter funnel, so it is the one that silently misses a new field.
        let collector = Self.collect("""
        @Injectable
        struct Cache<E> {
            let logger: Logger
            let serializer: Serializer<E>
        }
        """)

        let parameters = try #require(collector.types.first?.initializers.first?.parameters)
        #expect(parameters.count == 2)
        #expect(parameters[0].mentionedGenericParameters.isEmpty)
        #expect(parameters[1].mentionedGenericParameters == ["E"])
    }

    @Test("a nested type inherits the enclosing type's parameters")
    func nestedTypeInheritsTheScope() throws {
        // Swift keeps `E` in scope throughout the body of `Outer<E>`, so a
        // provider in a nested type can name it and Zerk has to agree.
        let collector = Self.collect("""
        struct Outer<E> {
            @Injectable
            struct Inner {
                @InjectableProviding
                init(serializer: Serializer<E>) {}
            }
        }
        """)

        let inner = try #require(collector.types.first { $0.name == "Inner" })
        // Inner declares none of its own...
        #expect(inner.genericParameters.isEmpty)
        // ...but reads its parameter in the enclosing scope.
        #expect(inner.initializers.first?.parameters.first?.mentionedGenericParameters == ["E"])
    }

    @Test("the scope is popped with the type that opened it")
    func scopeIsPoppedOnExit() throws {
        let collector = Self.collect("""
        struct Gone<E> {}

        @Injectable
        struct Later {
            @InjectableProviding
            init(serializer: Serializer<E>) {}
        }
        """)

        // `E` is out of scope here — `Serializer<E>` names a module type that
        // happens to be spelled `E`, whatever that is, not a free parameter.
        let later = try #require(collector.types.first { $0.name == "Later" })
        #expect(later.initializers.first?.parameters.first?.mentionedGenericParameters.isEmpty == true)
    }

    @Test("a non-generic graph records nothing generic")
    func nonGenericGraphIsUnaffected() throws {
        let collector = Self.collect("""
        @Injectable
        struct Logger {
            @InjectableProviding
            init(label: String) {}
        }
        """)

        let record = try #require(collector.types.first)
        #expect(record.genericParameters.isEmpty)
        let parameter = try #require(record.initializers.first?.parameters.first)
        #expect(parameter.mentionedGenericParameters.isEmpty)
        #expect(parameter.isBareGenericParameter == false)
    }

    // MARK: - Equality

    @Test("the generic facts stay out of parameter equality")
    func genericFactsDoNotAffectEquality() {
        // They describe the scope a parameter was read in, not the parameter.
        // Two identical `logger: Logger` parameters must stay interchangeable
        // even when one was declared inside a generic type — `mergeParameters`
        // dedupes on this.
        let plain = ParameterRecord(label: "logger", name: "logger",
                                    typeKey: "Logger", typeName: "Logger")
        var inGenericScope = plain
        inGenericScope.mentionedGenericParameters = ["E"]
        inGenericScope.isBareGenericParameter = true

        #expect(plain == inGenericScope)
    }
}
