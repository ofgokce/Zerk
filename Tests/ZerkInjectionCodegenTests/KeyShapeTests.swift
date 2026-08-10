//
//  KeyShapeTests.swift
//  Zerk
//

import Testing
import SwiftParser
import SwiftSyntax
@testable import CodegenToolkit
import SharedToolkit

/// Coverage of shape-based key matching: how a generic registration is filed,
/// and how a dependency for one specialization finds it.
///
/// The family lookups here are driven directly rather than through the pipeline,
/// so a failure names the matching rule rather than whatever was being generated
/// at the time. The end-to-end half lives in `GenericEmissionTests`, and the
/// degenerate half is worth keeping in mind: with no generic registrations,
/// `KeyIndex` is exactly the dictionary it replaced.
@Suite("Key shapes")
struct KeyShapeTests {

    private static func type(_ text: String) -> TypeSyntax {
        let file = Parser.parse(source: "func _probe(_ x: \(text)) {}")
        return file.statements.first!.item.as(FunctionDeclSyntax.self)!
            .signature.parameterClause.parameters.first!.type
    }

    // MARK: - Spelling

    @Test("a shape holes out one argument per parameter")
    func shapeSpelling() {
        #expect(KeyShape.text(base: "Cache", arity: 1) == "Cache<#0>")
        #expect(KeyShape.text(base: "Store", arity: 2) == "Store<#0, #1>")
        // Arity zero is not a family, so it is just the type.
        #expect(KeyShape.text(base: "Logger", arity: 0) == "Logger")
    }

    @Test("a shape is told apart from a type")
    func shapeRecognition() {
        #expect(KeyShape.isShape("Cache<#0>"))
        #expect(KeyShape.isShape("Store<#0, #1>"))
        #expect(KeyShape.isShape("Cache<String>") == false)
        #expect(KeyShape.isShape("Logger") == false)
        // The reason the hole is `#` and not `_`: SE-0315 placeholders make this
        // a key a real stored-property annotation can produce.
        #expect(KeyShape.isShape("Cache<_>") == false)
    }

    // MARK: - Reading a shape off a type

    @Test("a nominal generic application has a shape", arguments: [
        ("Cache<String>", "Cache<#0>"),
        ("Cache<Cache<Int>>", "Cache<#0>"),
        ("Store<String, Int>", "Store<#0, #1>"),
        ("any Caching<String>", "Caching<#0>"),
        ("(Cache<String>)", "Cache<#0>"),
        ("Outer.Cache<String>", "Outer.Cache<#0>"),
    ])
    func shapes(_ written: String, _ expected: String) {
        #expect(Self.type(written).typeKeyShape == expected)
    }

    @Test("anything a registration could never be has no shape", arguments: [
        "Logger",                 // not generic
        "Cache<String>?",         // Optional<Cache<String>> — not the thing itself
        "[Cache<String>]",        // Array<…>, and nothing registers Array
        "[String: Int]",
        "(Int) -> Cache<String>", // a function type
        "A & B",
        "some Caching<String>",   // opaque, a different thing from `any`
    ])
    func shapelessTypes(_ written: String) {
        #expect(Self.type(written).typeKeyShape == nil)
    }

    @Test("an optional key is unwrapped from its syntax")
    func optionalUnwrapping() {
        #expect(Self.type("Cache<String>?").unwrappedOptional?.typeKeyShape == "Cache<#0>")
        #expect(Self.type("Cache<String>!").unwrappedOptional?.typeKeyShape == "Cache<#0>")
        #expect(Self.type("Optional<Cache<String>>").unwrappedOptional?.typeKeyShape == "Cache<#0>")
        #expect(Self.type("Cache<String>").unwrappedOptional == nil)
    }

    // MARK: - The index

    private static func resolution(_ key: String, type: String) -> ProviderResolution {
        ProviderResolution(
            typeName: type,
            injectableKey: key,
            provider: .implicit(InitializerRecord(
                parameters: [], effects: .none,
                location: AttributeLocation(filePath: "", line: 1, column: 1))),
            isTypePrimary: false,
            isExported: false,
            isSingleton: false
        )
    }

    @Test("with no generic registrations the index is the dictionary it replaced")
    func groundOnlyIsADictionary() {
        let index = KeyIndex(["Logger": Self.resolution("Logger", type: "Logger")])

        #expect(index["Logger"]?.typeName == "Logger")
        #expect(index["Missing"] == nil)
        // No patterns, so nothing is ever asked for a shape.
        #expect(index["Cache<String>", shape: "Cache<#0>"] == nil)
    }

    @Test("a specialization is answered by its family")
    func specializationFindsItsFamily() {
        let index = KeyIndex(["Cache<#0>": Self.resolution("Cache<#0>", type: "Cache")])

        #expect(index["Cache<String>", shape: "Cache<#0>"]?.typeName == "Cache")
        #expect(index["Cache<Int>", shape: "Cache<#0>"]?.typeName == "Cache")
        // A different family, and a type with no shape at all.
        #expect(index["Store<String, Int>", shape: "Store<#0, #1>"] == nil)
        #expect(index["Logger", shape: nil] == nil)
    }

    @Test("an exact registration beats the family covering it")
    func exactBeatsFamily() {
        // Not a preference — agreement with the compiler. Given both overloads
        // Swift picks the concrete member at the call site, so resolving to the
        // generic one here would make Zerk's account of the graph disagree with
        // the code it emits.
        let index = KeyIndex([
            "Cache<#0>": Self.resolution("Cache<#0>", type: "GenericCache"),
            "Cache<String>": Self.resolution("Cache<String>", type: "StringCache"),
        ])

        #expect(index["Cache<String>", shape: "Cache<#0>"]?.typeName == "StringCache")
        // Every other specialization still falls to the family.
        #expect(index["Cache<Int>", shape: "Cache<#0>"]?.typeName == "GenericCache")
    }

    @Test("a registration key looks itself up")
    func shapeKeyIsItsOwnKey() {
        // `primaryResolutions[injectableKey]` asks with a *registration* key, not
        // a dependency's — for a generic family that key is already a shape.
        let index = KeyIndex(["Cache<#0>": Self.resolution("Cache<#0>", type: "Cache")])
        #expect(index["Cache<#0>"]?.typeName == "Cache")
    }

    @Test("values and entries cover both halves")
    func valuesAndEntries() {
        let index = KeyIndex([
            "Logger": Self.resolution("Logger", type: "Logger"),
            "Cache<#0>": Self.resolution("Cache<#0>", type: "Cache"),
        ])

        #expect(index.isEmpty == false)
        #expect(Set(index.values.map(\.typeName)) == ["Logger", "Cache"])
        #expect(Set(index.entries.map(\.key)) == ["Logger", "Cache<#0>"])
        #expect(KeyIndex<ProviderResolution>().isEmpty)
    }

    // MARK: - What gets registered

    private static func collect(_ source: String) -> SourceCollector {
        let collector = SourceCollector()
        collector.walk(Parser.parse(source: source))
        return collector
    }

    @Test("a generic type registers under its shape, not its name")
    func genericTypeRegistersUnderItsShape() throws {
        let collector = Self.collect("""
        @Injectable
        struct Cache<E> {
            @InjectableProviding
            init() {}
        }
        """)

        let record = try #require(collector.types.first)
        #expect(Array(record.injectableKeys.keys) == ["Cache<#0>"])
        // The bare name is not a type, and would collide with a non-generic
        // `Cache`; `Cache<E>` would file one family under as many keys as there
        // are ways to spell the parameter.
        #expect(record.injectableKeys["Cache"] == nil)
        // The spelling the emitter will want is kept alongside.
        #expect(collector.keyDisplayNames["Cache<#0>"] == "Cache<E>")
    }

    @Test("arity is part of the shape")
    func arityIsPartOfTheShape() throws {
        let collector = Self.collect("""
        @Injectable
        struct Store<K, V> {
            @InjectableProviding
            init() {}
        }
        """)

        let record = try #require(collector.types.first)
        #expect(Array(record.injectableKeys.keys) == ["Store<#0, #1>"])
        #expect(collector.keyDisplayNames["Store<#0, #1>"] == "Store<K, V>")
    }

    @Test("a non-generic type still registers under its own name")
    func nonGenericRegistrationIsUnchanged() throws {
        let collector = Self.collect("""
        @Injectable
        struct Logger {
            @InjectableProviding
            init() {}
        }
        """)

        let record = try #require(collector.types.first)
        #expect(Array(record.injectableKeys.keys) == ["Logger"])
    }

    @Test("a dependency records the shape that would find its family")
    func dependencyRecordsItsShape() throws {
        let collector = Self.collect("""
        @Injectable
        struct Screen {
            @InjectableProviding
            init(cache: Cache<String>, logger: Logger) {}
        }
        """)

        let parameters = try #require(collector.types.first?.initializers.first?.parameters)
        #expect(parameters[0].typeKey == "Cache<String>")
        #expect(parameters[0].typeKeyShape == "Cache<#0>")
        #expect(parameters[1].typeKeyShape == nil)
    }
}
