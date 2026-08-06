//
//  MemberNamingTests.swift
//  Zerk
//

import Testing
@testable import CodegenToolkit

/// Coverage of the type-name → member-name rule, which every generated member
/// that is not named outright goes through.
///
/// Lowercasing the first character alone is not enough: it turns `URLSession`
/// into `uRLSession`, which reads as a typo rather than as a name. The Swift API
/// Design Guidelines say an acronym beginning a lowerCamelCase name is
/// lowercased whole, and that is what this implements.
@Suite("Member naming")
struct MemberNamingTests {

    @Test("a leading acronym is lowercased whole", arguments: [
        // The ordinary case: one leading capital.
        ("ApiService", "apiService"),
        ("Session", "session"),
        ("Loader", "loader"),
        // A leading acronym, with the last capital starting the next word.
        ("URLSession", "urlSession"),
        ("APIService", "apiService"),
        ("HTTPClient", "httpClient"),
        ("JSONStore", "jsonStore"),
        ("UICache", "uiCache"),
        ("SQLiteStore", "sqLiteStore"),
        // The whole name is an acronym — there is no next word to protect.
        ("URL", "url"),
        ("ID", "id"),
        ("A", "a"),
        // A digit ends the acronym, so the run is one word.
        ("UTF8Decoder", "utf8Decoder"),
        ("URL2", "url2"),
        // Already lowerCamel, or not a letter at all: untouched.
        ("apiService", "apiService"),
        ("", ""),
    ])
    func leadingAcronymIsLowercased(input: String, expected: String) {
        #expect(input.memberNameForType == expected)
    }

    @Test("a plural acronym keeps its trailing letter", arguments: [
        ("URLs", "urls"),
        ("IDs", "ids"),
        ("APIs", "apis"),
    ])
    func pluralAcronymsAreOneWord(input: String, expected: String) {
        // A single letter after the run is a plural rather than a word, so the
        // whole run is lowercased. `URLId` loses to this heuristic and gives
        // `urlid` — nothing in the spelling tells the two apart, and the plural
        // is the far likelier type name. `@Injectable(name:)` is the way out.
        #expect(input.memberNameForType == expected)
    }

    @Test("a nested type keeps only its last component", arguments: [
        ("Keychain.Store", "store"),
        ("Keychain.URLStore", "urlStore"),
        ("Foo.Bar.Baz", "baz"),
    ])
    func nestedTypesDropTheQualification(input: String, expected: String) {
        // `keychain.Store` is not an identifier, and the qualification says
        // where the type lives rather than what it is called.
        #expect(input.memberNameForType == expected)
    }

    // MARK: - End to end

    @Test("an acronym-named injectable generates a readable member")
    func acronymInjectableEndToEnd() throws {
        let source = """
        @Injectable
        final class APIService {
            init() {}
        }

        @Injectable
        final class HTTPClient {
            init(service: APIService) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("static var apiService: APIService {"))
        // A type dependency resolves through the key's primary rather than by
        // member name, so the rule shows up on the member and on its own
        // `static var` — not in the default expression.
        #expect(result.output.output.contains(
            "static func httpClient(service: APIService = Zerk<APIService>.inject()) -> HTTPClient {"))
        #expect(result.output.output.contains("static var httpClient: HTTPClient {"))
        // The spelling this rule exists to prevent.
        #expect(!result.output.output.contains("aPIService"))
        #expect(!result.output.output.contains("hTTPClient"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("the interjection point follows the member's name")
    func interjectionPointUsesTheSameRule() {
        let output = CompileFixture.generate(source: """
        @Injectable
        final class URLSessionStore {
            init() {}
        }
        """)

        #expect(output.contains("var `urlSessionStore`: Void {}"))
        #expect(output.contains("if let interjected = _$interjected(for: \\.`urlSessionStore`)"))
    }

    @Test("singleton storage is named by the same rule")
    func singletonStorageUsesTheSameRule() throws {
        // Storage sits in a generated enum rather than on `Zerk<Key>`, and is
        // named from the type independently of the member — so it needs the
        // rule too, or the generated file mixes both spellings.
        let source = """
        protocol Storing {}

        @Singleton
        @Injectable<Storing>
        final class JSONStore: Storing {
            init() {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("static let jsonStore: JSONStore = JSONStore()"))
        #expect(result.output.output.contains("return _$zerk_singletons.jsonStore"))
        #expect(!result.output.output.contains("jSONStore"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("typeNamed: goes through the same rule")
    func typeNamedUsesTheSameRule() {
        let output = CompileFixture.generate(source: """
        protocol Sessioning {}
        final class URLSession: Sessioning { init() {} }

        @Injectable<Sessioning>(typeNamed: true)
        var dummyName: URLSession { .init() }
        """)

        #expect(output.contains("static var urlSession: Sessioning {"))
        #expect(!output.contains("uRLSession"))
    }
}
