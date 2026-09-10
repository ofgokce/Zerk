//
//  ModuleQualifiedKeyTests.swift
//  Zerk
//

import Testing
@testable import CodegenToolkit

/// `Core.Foo` and `Foo` are one type, and Zerk used to match them as two keys —
/// so a dependency written with the module name silently bubbled up to the
/// caller instead of resolving.
///
/// The qualifier is dropped for exactly the modules the file imports, which is
/// also the set the generated file imports — Zerk copies them across. That is
/// what makes the short spelling safe to emit.
@Suite("Module-qualified keys")
struct ModuleQualifiedKeyTests {

    // MARK: - The stripping rule itself

    @Test("a known module's qualifier is dropped", arguments: [
        ("Core.Foo", "Foo"),
        ("Array<Core.Foo>", "Array<Foo>"),
        ("Optional<Core.Foo>", "Optional<Foo>"),
        ("Dictionary<Core.Key, Core.Value>", "Dictionary<Key, Value>"),
        ("Core.A & Core.B", "A & B"),
        ("(Core.A) -> Core.B", "(A) -> B"),
        ("any Core.Serving", "any Serving"),
        // The module goes, the nesting stays.
        ("Core.Outer.Inner", "Outer.Inner")
    ])
    func stripsKnownModules(input: String, expected: String) {
        #expect(KeyAliases.unqualified(input, modules: ["Core"]) == expected)
    }

    @Test("anything that is not a known module is left alone", arguments: [
        // A nested type, not a module — and indistinguishable from one by
        // syntax alone, which is why the known-module set is the boundary.
        "Outer.Inner",
        "Foo",
        "Array<Outer.Inner>"
    ])
    func leavesUnknownQualifiersAlone(input: String) {
        #expect(KeyAliases.unqualified(input, modules: ["Core"]) == input)
    }

    // MARK: - Swift is implicit

    @Test("Swift needs no import at all, so it never has to be declared")
    func swiftIsImplicit() {
        // Declared nothing, imported nothing.
        let aliases = KeyAliases(declarations: [])

        #expect(aliases.representative(for: "Swift.String") == "String")
        #expect(aliases.representative(for: "Array<Swift.String>") == "Array<String>")
        #expect(aliases.representative(for: "Swift.Optional<Swift.Int>") == "Optional<Int>")
        // The language guarantees `Swift` is in scope in every file, generated
        // ones included, so the short spelling always resolves. No other module
        // gets this — `Foundation.Date` still needs its import.
        #expect(aliases.representative(for: "Foundation.Date") == "Foundation.Date")
    }

    @Test("a Swift-qualified dependency resolves against the plain key")
    func swiftQualifiedDependencyResolves() {
        let result = CompileFixture.generateWithResolution(source: """
        @InjectableValue
        var baseURL: Swift.String { "https://example.com" }

        @Injectable
        struct Consumer {
            @InjectableProviding
            init(baseURL: String) {}
        }
        """)

        #expect(result.diagnostics.filter { $0.severity == .error }.isEmpty)
        // The value is keyed `String`, the parameter asks for `String`, and the
        // two used to be different keys.
        #expect(result.output.output.contains("extension Zerk<String>"))
        #expect(result.output.output.contains("nonisolated static func inject() -> Consumer"))
    }

    @Test("Swift is not added to the generated file's imports")
    func swiftIsNotImported() {
        let output = CompileFixture.generate(source: """
        @Injectable
        struct Consumer {
            @InjectableProviding
            init(name: Swift.String) {}
        }
        """)

        // Stripping needs no import here, and `import Swift` in generated code
        // would be noise.
        #expect(!output.contains("import Swift"))
    }

    @Test("a qualifier is only dropped where a type reference starts")
    func onlyStripsAtAReferenceStart() {
        // `Core` here is the *nested* name, not the module: dropping it would
        // change which type the key names.
        #expect(KeyAliases.unqualified("Outer.Core.Inner", modules: ["Core"]) == "Outer.Core.Inner")
    }

    @Test("a name merely starting with a module's name is untouched")
    func respectsIdentifierBoundaries() {
        #expect(KeyAliases.unqualified("CoreKit.Foo", modules: ["Core"]) == "CoreKit.Foo")
        #expect(KeyAliases.unqualified("MyCore.Foo", modules: ["Core"]) == "MyCore.Foo")
    }

    @Test("with no known modules nothing changes")
    func noModulesIsIdentity() {
        #expect(KeyAliases.unqualified("Core.Foo", modules: []) == "Core.Foo")
    }

    // MARK: - Through the pipeline

    private static let source = """
    import Core

    @Injectable
    struct Consumer {
        @InjectableProviding
        init(api: Core.ApiServicing) {}
    }

    enum Imports {
        @ImportedInjectable
        static func api() -> ApiServicing { Zerk<ApiServicing>.inject() }
    }
    """

    @Test("a module-qualified dependency resolves against the unqualified key")
    func qualifiedDependencyResolves() {
        let result = CompileFixture.generateWithResolution(source: Self.source)
        #expect(result.diagnostics.filter { $0.severity == .error }.isEmpty)

        // The fix: this used to bubble `api` up as a caller-supplied parameter.
        #expect(result.output.output.contains("Zerk<ApiServicing>.inject()"))
        #expect(result.output.output.contains("nonisolated static func inject() -> Consumer"))
    }

    @Test("the parameter keeps the spelling the developer wrote")
    func parameterSpellingIsPreserved() {
        let output = CompileFixture.generate(source: Self.source)
        // Only the *key* is canonicalized. The declared type stays as written,
        // the same rule canonicalization has always followed.
        #expect(output.contains("api: Core.ApiServicing"))
    }

    @Test("the graph records one key, not two")
    func graphHasOneKey() {
        let graph = CompileFixture.graph(source: Self.source)
        let dependency = graph.keys
            .first { $0.key == "Consumer" }?
            .providers.first?.dependencies.first

        #expect(graph.keys.map(\.key).sorted() == ["ApiServicing", "Consumer"])
        #expect(dependency?.source == "injectable")
        #expect(dependency?.key == "ApiServicing")
    }

    @Test("without the import the qualifier stands, and the dependency does not resolve")
    func withoutTheImportNothingIsStripped() {
        let source = Self.source.replacingOccurrences(of: "import Core", with: "")
        let output = CompileFixture.generate(source: source)

        // Deliberate: an unimported prefix may be a nested type, and stripping
        // it would both mis-key the dependency and emit a name the generated
        // file cannot resolve.
        #expect(output.contains("api: Core.ApiServicing"))
        #expect(!output.contains("nonisolated static func inject() -> Consumer {"))
    }

    @Test("registering under a qualified key is reached by the unqualified one")
    func qualifiedRegistrationMatchesUnqualifiedUse() {
        let result = CompileFixture.generateWithResolution(source: """
        import Core

        @Injectable<Core.Serving>
        struct Live: Core.Serving {
            @InjectableProviding
            init() {}
        }

        @Injectable
        struct Consumer {
            @InjectableProviding
            init(serving: Serving) {}
        }
        """)

        #expect(result.diagnostics.filter { $0.severity == .error }.isEmpty)
        // One key, one extension — not `Zerk<Core.Serving>` and `Zerk<Serving>`
        // side by side, which is the shape that fails to compile.
        #expect(result.output.output.contains("extension Zerk<Serving> {"))
        #expect(!result.output.output.contains("extension Zerk<Core.Serving> {"))
        #expect(result.output.output.contains("Zerk<Serving>.inject()"))
    }

    @Test("an alias declared against either spelling joins one group")
    func aliasesComposeWithQualification() {
        let aliases = KeyAliases(
            declarations: [
                AliasDeclaration(
                    keys: ["Core.Storing", "Persisting"],
                    aliasKey: "Persisting",
                    location: AttributeLocation(filePath: "F.swift", line: 1, column: 1)
                )
            ],
            knownModules: ["Core"]
        )

        // Qualification is resolved first, so both spellings land in the same
        // group and the alias still elects the underlying type.
        #expect(aliases.representative(for: "Core.Storing") == "Storing")
        #expect(aliases.representative(for: "Storing") == "Storing")
        #expect(aliases.representative(for: "Persisting") == "Storing")
    }
}
