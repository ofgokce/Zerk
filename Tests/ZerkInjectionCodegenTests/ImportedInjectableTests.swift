//
//  ImportedInjectableTests.swift
//  Zerk
//

import Testing
@testable import CodegenToolkit

/// Coverage of `@ImportedInjectable`, which is how a module's graph reaches a key
/// that lives in another module.
///
/// Zerk resolves within one module. An import describes a foreign key well
/// enough to satisfy a local provider's parameter — and nothing more: it emits no
/// members, because what it resolves is built elsewhere.
@Suite("@ImportedInjectable")
struct ImportedInjectableTests {

    @Test("an imported key satisfies a local provider's parameter")
    func importSatisfiesALocalParameter() {
        let source = """
        protocol Session {}

        enum ZerkImports {
            @ImportedInjectable
            static func session() -> Session
        }

        @Injectable
        final class Repo {
            @InjectableProviding
            init(session: Session) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("session: Session = Zerk<Session>.inject()"))
        // Fully resolved, so nothing bubbles to the caller.
        #expect(result.output.output.contains("static func inject() -> Repo"))
    }

    @Test("no members are generated for an imported key")
    func importEmitsNoMembers() {
        // The key is built in another module; emitting `extension Zerk<Session>`
        // here would be a second, local definition of someone else's dependency.
        let source = """
        protocol Session {}

        enum ZerkImports {
            @ImportedInjectable
            static func session() -> Session
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(!result.output.output.contains("extension Zerk<Session>"))
    }

    @Test("a body names the member to resolve through")
    func bodyNamesTheMember() {
        let source = """
        protocol Session {}

        enum ZerkImports {
            @ImportedInjectable
            static func session() -> Session { Zerk<Session>.staging }
        }

        @Injectable
        final class Repo {
            @InjectableProviding
            init(session: Session) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        // A property takes no parentheses, however the declaration was written.
        #expect(result.output.output.contains("session: Session = Zerk<Session>.staging)"))
        #expect(!result.output.output.contains("Zerk<Session>.staging()"))
    }

    @Test("a call-form body keeps its parentheses and forwards parameters")
    func callFormBodyForwardsParameters() {
        let source = """
        protocol Session {}

        enum ZerkImports {
            @ImportedInjectable
            static func session(id: Int) -> Session { Zerk<Session>.seeded(id: id) }
        }

        @Injectable
        final class Repo {
            @InjectableProviding
            init(session: Session) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        // `id` is nobody's to supply here, so it bubbles onto inject().
        #expect(result.output.output.contains("static func inject(id: Int) -> Repo"))
        #expect(result.output.output.contains("Zerk<Session>.seeded(id: id)"))
    }

    @Test("effects and isolation are taken from the declaration")
    func effectsAndIsolationPropagate() {
        let source = """
        protocol Session {}

        enum ZerkImports {
            @ImportedInjectable
            static func session() async throws -> Session
        }

        @Injectable
        final class Repo {
            @InjectableProviding
            init(session: Session) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.output.output.contains("async throws -> Repo"))
        #expect(result.output.output.contains("try await Zerk<Session>.inject()"))
    }

    @Test("a key both imported and declared locally is an error")
    func importConflictingWithLocalIsAnError() {
        let source = """
        protocol Session {}

        enum ZerkImports {
            @ImportedInjectable
            static func session() -> Session
        }

        @Injectable<Session>
        final class LocalSession: Session {
            @InjectableProviding
            init() {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.contains {
            $0.severity == .error
                && $0.message.contains("both imported and declared @Injectable in this module")
        })
    }

    @Test("importing one key twice is an error")
    func duplicateImportIsAnError() {
        // Only one import can be *the* resolution for a key; a second is a
        // choice Zerk cannot make.
        let source = """
        protocol Session {}

        enum ZerkImports {
            @ImportedInjectable
            static func session() -> Session

            @ImportedInjectable
            static func staging() -> Session { Zerk<Session>.staging }
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.contains {
            $0.severity == .error && $0.message.contains("is imported more than once")
        })
    }

    @Test("where the declaration sits makes no difference", arguments: [
        "@ImportedInjectable\nfunc session() -> Session",
        "private enum I {\n    @ImportedInjectable\n    static func session() -> Session\n}",
        "enum I {\n    @ImportedInjectable\n    func session() -> Session\n}",
    ])
    func placementIsIrrelevant(_ declaration: String) {
        // Nothing calls these, so visibility, staticness and nesting are free.
        let source = """
        protocol Session {}

        \(declaration)

        @Injectable
        final class Repo {
            @InjectableProviding
            init(session: Session) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("static func inject() -> Repo"))
    }
}
