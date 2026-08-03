//
//  ImportedInjectableValueTests.swift
//  Zerk
//

import Testing
@testable import CodegenToolkit

/// Coverage of `@ImportedInjectableValue`, which is how a module's graph reaches
/// a *value* declared in another module.
///
/// Values are matched by key **and name** together, which is what keeps two
/// unrelated `String`s apart. Importing one through `@ImportedInjectable` would
/// discard the name and register it as the key's primary, letting a single
/// `String` answer for every `String` parameter in the module — so values need
/// their own import, and that difference is what most of these cases pin.
@Suite("@ImportedInjectableValue")
struct ImportedInjectableValueTests {

    // MARK: - Matching

    @Test("an imported value satisfies a parameter of the same name")
    func importSatisfiesAParameter() {
        let source = """
        enum ZerkImports {
            @ImportedInjectableValue
            static var baseURL: String { Zerk<String>.baseURL }
        }

        @Injectable
        final class Repo {
            @InjectableProviding
            init(baseURL: String) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("baseURL: String = Zerk<String>.baseURL"))
        #expect(result.output.output.contains("static func inject() -> Repo"))
    }

    @Test("several values of one key stay distinct")
    func severalValuesOfOneKeyCoexist() {
        // The case `@ImportedInjectable` cannot express at all: it registers one
        // primary per key, so a second `String` is rejected as a duplicate
        // import and the first answers for every `String` parameter.
        let source = """
        enum ZerkImports {
            @ImportedInjectableValue
            static var baseURL: String { Zerk<String>.baseURL }

            @ImportedInjectableValue
            static var apiKey: String { Zerk<String>.apiKey }
        }

        @Injectable
        final class Repo {
            @InjectableProviding
            init(baseURL: String, apiKey: String) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("baseURL: String = Zerk<String>.baseURL"))
        #expect(result.output.output.contains("apiKey: String = Zerk<String>.apiKey"))
    }

    @Test("an import may be renamed, reading one member under another name")
    func importMayBeRenamed() {
        // The name on the left is what parameters match; the member on the right
        // is what gets read. A module whose parameters spell it differently does
        // not have to rename them.
        let source = """
        enum ZerkImports {
            @ImportedInjectableValue
            static var headline: String { Zerk<String>.banner }
        }

        @Injectable
        final class Repo {
            @InjectableProviding
            init(headline: String) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("headline: String = Zerk<String>.banner"))
        #expect(!result.output.output.contains("Zerk<String>.headline"))
    }

    @Test("a parameter matching no imported name is left to the caller")
    func unmatchedParameterBubbles() {
        // The regression this whole macro exists for: under `@ImportedInjectable`
        // the single imported `String` answered here too, silently.
        let source = """
        enum ZerkImports {
            @ImportedInjectableValue
            static var baseURL: String { Zerk<String>.baseURL }
        }

        @Injectable
        final class Repo {
            @InjectableProviding
            init(somethingElse: String) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(!result.output.output.contains("somethingElse: String = "))
        #expect(result.output.output.contains("static func inject(somethingElse: String) -> Repo"))
    }

    // MARK: - Emission

    @Test("no member is generated for an imported value")
    func importEmitsNoMember() {
        // The member belongs to the module that declares the value; emitting one
        // here would redeclare someone else's dependency on the same
        // specialization.
        let source = """
        enum ZerkImports {
            @ImportedInjectableValue
            static var baseURL: String { Zerk<String>.baseURL }
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(!result.output.output.contains("extension Zerk<String>"))
        // The interjection requirement goes with the member, so it stays away too.
        #expect(!result.output.output.contains("InterjectingString"))
    }

    @Test("a local value on the same key is still emitted alongside an import")
    func localValuesSurviveAnImport() {
        let source = """
        enum ZerkImports {
            @ImportedInjectableValue
            static var baseURL: String { Zerk<String>.baseURL }
        }

        @InjectableValue
        var localTag: String { "local" }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("static var localTag: String"))
        #expect(!result.output.output.contains("static var baseURL: String"))
    }

    // MARK: - Isolation

    @Test("an imported value's isolation reaches the resolution")
    func isolationPropagates() {
        let source = """
        enum ZerkImports {
            @ImportedInjectableValue
            @MainActor
            static var baseURL: String { Zerk<String>.baseURL }
        }

        @Injectable
        final class Repo {
            @InjectableProviding
            init(baseURL: String) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        // A nonisolated provider reaching a MainActor value crosses a domain, so
        // it resolves in the body with an await rather than in a default.
        #expect(result.output.output.contains("await Zerk<String>.baseURL"))
        #expect(result.output.output.contains("static func inject() async -> Repo"))
    }

    // MARK: - Aliases

    @Test("an imported value's key folds onto its alias representative")
    func aliasRewritingReachesImports() {
        let source = """
        @ZerkAlias
        typealias Handle = String

        enum ZerkImports {
            @ImportedInjectableValue
            static var baseURL: Handle { Zerk<String>.baseURL }
        }

        @Injectable
        final class Repo {
            @InjectableProviding
            init(baseURL: String) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        // Keyed `Handle`, folded to `String`, so the `String` parameter matches.
        #expect(result.output.output.contains("baseURL: String = Zerk<String>.baseURL"))
    }

    // MARK: - Diagnostics

    @Test("an import colliding with a local value of the same name is an error")
    func localCollisionIsAnError() {
        let source = """
        enum ZerkImports {
            @ImportedInjectableValue
            static var baseURL: String { Zerk<String>.baseURL }
        }

        @InjectableValue
        var baseURL: String { "local" }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.contains {
            $0.severity == .error
                && $0.message.contains("'baseURL' is imported as a 'String' value")
                && $0.message.contains("already declares one")
        })
    }

    @Test("the same name imported twice is an error")
    func duplicateImportIsAnError() {
        let source = """
        enum ZerkImports {
            @ImportedInjectableValue
            static var baseURL: String { Zerk<String>.baseURL }
        }

        enum MoreImports {
            @ImportedInjectableValue
            static var baseURL: String { Zerk<String>.other }
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.contains {
            $0.severity == .error && $0.message.contains("'baseURL' is imported more than once")
        })
    }

    @Test("the same key under different names is not a conflict")
    func sameKeyDifferentNamesIsFine() {
        // The whole point: a key import collides with another of its key, a
        // value import only with another of its *name*.
        let source = """
        enum ZerkImports {
            @ImportedInjectableValue
            static var baseURL: String { Zerk<String>.baseURL }

            @ImportedInjectableValue
            static var apiKey: String { Zerk<String>.apiKey }

            @ImportedInjectableValue
            static var banner: String { Zerk<String>.banner }
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
    }

    @Test("a value import does not conflict with a key import of the same type")
    func keyAndValueImportsAreIndependent() {
        let source = """
        protocol Session {}

        enum ZerkImports {
            @ImportedInjectable
            static func session() -> Session

            @ImportedInjectableValue
            static var fallback: Session { Zerk<Session>.fallback }
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
    }

    @Test("an unreadable getter is not collected")
    func malformedGetterIsSkipped() {
        // The macro reports the shape; the plugin simply does not register it,
        // rather than reporting the same thing a second time.
        let source = """
        enum ZerkImports {
            @ImportedInjectableValue
            static var baseURL: String { compute() }
        }

        @Injectable
        final class Repo {
            @InjectableProviding
            init(baseURL: String) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(!result.output.output.contains("= Zerk<String>.baseURL"))
        #expect(result.output.output.contains("static func inject(baseURL: String) -> Repo"))
    }
}
