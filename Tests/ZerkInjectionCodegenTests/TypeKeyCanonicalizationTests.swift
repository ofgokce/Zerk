//
//  TypeKeyCanonicalizationTests.swift
//  Zerk
//

import SwiftParser
import SwiftSyntax
import Testing
@testable import CodegenToolkit
@testable import SharedToolkit

/// Coverage of the type-key canonicalizer.
///
/// Swift lets one type be written several ways, and Zerk matches dependencies by
/// key, so `[String]` and `Array<String>` used to be different dependencies. The
/// rules here are only the ones decidable from syntax alone — Zerk resolves
/// nothing — and the "stay distinct" half matters as much as the "become equal"
/// half, since over-merging silently wires up the wrong provider.
@Suite("Type key canonicalization")
struct TypeKeyCanonicalizationTests {

    /// Parses a bare type by wrapping it in a declaration, so the tests exercise
    /// real parsed syntax rather than a hand-built tree.
    private func parse(_ source: String) -> TypeSyntax {
        let file = Parser.parse(source: "let _probe: \(source)")
        guard let variable = file.statements.first?.item.as(VariableDeclSyntax.self),
              let type = variable.bindings.first?.typeAnnotation?.type else {
            Issue.record("could not parse type '\(source)'")
            return TypeSyntax(IdentifierTypeSyntax(name: .identifier("<unparsed>")))
        }
        return type
    }

    private func key(_ source: String) -> String {
        parse(source).normalizedTypeKey
    }

    private func display(_ source: String) -> String {
        parse(source).displayTypeKey
    }

    // MARK: - Spellings that become one key

    @Test("sugar and its explicit generic spelling agree", arguments: [
        ("[String]", "Array<String>"),
        ("[String: Int]", "Dictionary<String, Int>"),
        ("String?", "Optional<String>"),
        ("String!", "Optional<String>"),
        ("String!", "String?"),
        ("()", "Void"),
        ("(String)", "String"),
    ])
    func sugarAgreesWithExplicitSpelling(_ sugared: String, _ explicit: String) {
        #expect(key(sugared) == key(explicit))
    }

    @Test("canonicalization recurses through nested sugar", arguments: [
        ("[String]?", "Optional<Array<String>>"),
        ("[[String]]", "Array<Array<String>>"),
        ("String??", "Optional<Optional<String>>"),
        ("[String: [Int]?]", "Dictionary<String, Optional<Array<Int>>>"),
        ("[String: Int]?", "Optional<Dictionary<String, Int>>"),
    ])
    func nestedSugarCanonicalizes(_ sugared: String, _ explicit: String) {
        #expect(key(sugared) == key(explicit))
    }

    @Test("protocol composition is unordered")
    func compositionIsUnordered() {
        #expect(key("A & B") == key("B & A"))
        #expect(key("A & B & C") == key("C & A & B"))
        // Safe with a class constraint too: Base & P and P & Base are one type.
        #expect(key("Base & P") == key("P & Base"))
    }

    @Test("whitespace never changes a key")
    func whitespaceIsIgnored() {
        #expect(key("[String : Int]") == key("[String: Int]"))
        #expect(key("Dictionary<String,Int>") == key("Dictionary<String, Int>"))
        #expect(key("A&B") == key("A & B"))
    }

    @Test("any is stripped for matching")
    func anyIsStrippedForMatching() {
        #expect(key("any Serving") == key("Serving"))
        #expect(key("any A & B") == key("A & B"))
        #expect(key("Optional<any Serving>") == key("Serving?"))
    }

    // MARK: - Spellings that must stay distinct

    @Test("genuinely different types are not merged", arguments: [
        ("(x: Int, y: Int)", "(Int, Int)"),
        ("() throws -> Void", "() -> Void"),
        ("() async -> Void", "() -> Void"),
        ("@Sendable () -> Void", "() -> Void"),
        ("some P", "any P"),
        ("P.Type", "P"),
        ("Int32", "Int"),
        ("[Int]", "Set<Int>"),
        ("[String: Int]", "[Int: String]"),
    ])
    func lookalikesStayDistinct(_ lhs: String, _ rhs: String) {
        #expect(key(lhs) != key(rhs))
    }

    @Test("module qualification is left alone")
    func moduleQualificationIsPreserved() {
        // Would need type resolution: `A.Foo` and `B.Foo` are different types
        // that both reduce to `Foo`.
        #expect(key("Swift.String") != key("String"))
    }

    // MARK: - Display spelling

    @Test("display keeps any exactly as written")
    func displayPreservesAny() {
        #expect(display("any Serving") == "any Serving")
        #expect(display("Serving") == "Serving")
        // Never added — `any` is illegal on a class or struct, and Zerk reads
        // tokens so it cannot tell which a key is.
        #expect(display("Base") == "Base")
    }

    @Test("display canonicalizes everything except any")
    func displayCanonicalizesTheRest() {
        #expect(display("[String]") == "Array<String>")
        #expect(display("String?") == "Optional<String>")
        #expect(display("Array<any P>") == "Array<any P>")
    }
}

/// The canonicalizer's effect on the pipeline: spellings that differ across
/// declarations now resolve to one another.
@Suite("Type key canonicalization (end to end)")
struct TypeKeyCanonicalizationPipelineTests {

    @Test("a value and a parameter spelled differently now resolve")
    func differentSpellingsResolve() {
        let source = """
        @InjectableValue
        var names: [String] { ["a"] }

        protocol Serving {}

        @Injectable<Serving>
        final class Svc: Serving {
            @InjectableProviding
            init(names: Array<String>) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        // Resolved rather than bubbled up to the caller.
        #expect(result.output.output.contains("Zerk<Array<String>>.names"))
        #expect(result.output.output.contains("static func inject() -> Serving"))
        #expect(!result.output.output.contains("inject(names:"))
        // Declaration and read agree on one spelling.
        #expect(result.output.output.contains("extension Zerk<Array<String>> {"))
        #expect(!result.output.output.contains("Zerk<[String]>"))
    }

    @Test("a key written with any keeps it in the generated file")
    func anyKeyIsPreserved() throws {
        let source = """
        protocol Serving {}

        @Injectable<any Serving>
        final class Svc: Serving {
            @InjectableProviding
            init() {}
        }
        """

        let result = try CompileFixture.run(source: source)

        #expect(result.generated.contains("extension Zerk<any Serving> {"))
        #expect(result.generated.contains("-> any Serving"))
        // `any Serving?` is a parse error; the requirement has to parenthesize.
        #expect(result.generated.contains("(any Serving)?"))
        // The protocol name stays on the canonical key, so writing `any` cannot
        // rename it out from under an existing conformance.
        #expect(result.generated.contains("protocol InterjectingServing {"))

        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(result.didCompile, Comment(rawValue: result.compilerOutput))
    }

    @Test("a class key never gains any")
    func classKeyNeverGainsAny() throws {
        let source = """
        class Base {}

        @Injectable<Base>
        final class Sub: Base {
            @InjectableProviding
            override init() {}
        }
        """

        let result = try CompileFixture.run(source: source)

        // `any Base` is 'any' has no effect on concrete type — a hard error.
        #expect(result.generated.contains("extension Zerk<Base> {"))
        #expect(!result.generated.contains("any Base"))

        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(result.didCompile, Comment(rawValue: result.compilerOutput))
    }

    @Test("when spellings disagree, any wins and the key unifies")
    func anyTakesPrecedence() throws {
        let source = """
        protocol Serving {}

        @Injectable<Serving>(primary: true)
        final class A: Serving {
            @InjectableProviding
            init() {}
        }

        @Injectable<any Serving>
        final class B: Serving {
            @InjectableProviding
            init() {}
        }
        """

        let result = try CompileFixture.run(source: source)

        // One extension, not two: bare and `any` are the same specialization, so
        // emitting both would redeclare the members.
        let extensionCount = result.generated
            .components(separatedBy: "extension Zerk<").count - 1
        #expect(extensionCount == 1)
        #expect(result.generated.contains("extension Zerk<any Serving> {"))
        #expect(result.generated.contains("static var a: any Serving"))
        #expect(result.generated.contains("static var b: any Serving"))

        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(result.didCompile, Comment(rawValue: result.compilerOutput))
    }

    @Test("an optional @Injected property still resolves its unwrapped key")
    func optionalInjectedUnwraps() {
        // `?` is `Optional<…>` after canonicalization, so the unwrap that used
        // to be spelled three ways is now one.
        let source = """
        protocol Serving {}

        @Injectable<Serving>
        final class Svc: Serving {
            @InjectableProviding
            init() {}
        }

        struct Consumer {
            @Injected
            var service: Serving?
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
    }
}
