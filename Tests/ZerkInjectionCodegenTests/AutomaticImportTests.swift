//
//  AutomaticImportTests.swift
//  Zerk
//

import Testing
@testable import CodegenToolkit

/// The generated file's imports, which it now takes from the files it read.
///
/// `#ZerkImport(module:)` used to carry this, and restating was the part that
/// went wrong: forget it and the failure is a missing name inside a file nobody
/// wrote, arriving whenever somebody touches a foreign type. Copying the imports
/// is correct by construction instead — a declaration mentioning `Date` sits in
/// a file that imports `Foundation`, or that file would not compile — so the set
/// can only ever be a superset of what is needed, and can never be short.
@Suite("Automatic imports")
struct AutomaticImportTests {

    @Test("a file's imports reach the generated file")
    func importsAreCopied() {
        let generated = CompileFixture.generate(source: """
        import Foundation
        import Combine

        protocol Repo {}
        @Injectable<Repo>
        struct LiveRepo: Repo {}
        """)

        #expect(generated.contains("\nimport Combine"))
        #expect(generated.contains("\nimport Foundation"))
    }

    /// The case `#ZerkImport` existed for, and the one that shows the union has
    /// to be over *emitted* names rather than registrations: nothing here is
    /// `@Injectable`, yet the overload reproduces `Date` in its own signature.
    @Test("an @injected overload's own parameter types are covered")
    func overloadParameterTypesAreCovered() {
        let generated = CompileFixture.generate(source: """
        import Foundation

        protocol Repo {}
        @Injectable<Repo>
        struct LiveRepo: Repo {}

        public struct Screen {
            public init(@injected repo: Repo, stamp: Date) {}
        }
        """)

        #expect(generated.contains("stamp: Date"))
        #expect(generated.contains("\nimport Foundation"))
    }

    @Test("Zerk's own import is not duplicated")
    func zerkIsNotDuplicated() {
        let generated = CompileFixture.generate(source: """
        import Zerk

        @Injectable
        struct Service {}
        """)

        #expect(generated.components(separatedBy: "import Zerk").count == 2)
    }

    /// A test target's `@testable import` belongs to that target. Reproducing it
    /// in the generated file is either an error or a claim about visibility the
    /// module cannot back.
    @Test("@testable is not carried across")
    func testableIsNotCarried() {
        let generated = CompileFixture.generate(source: """
        @testable import Foundation
        import Combine

        @Injectable
        struct Service {}
        """)

        #expect(!generated.contains("import Foundation"))
        #expect(!generated.contains("@testable"))
        #expect(generated.contains("\nimport Combine"))
    }

    @Test("a guarded import keeps its guard")
    func guardedImportKeepsItsGuard() {
        let generated = CompileFixture.generate(source: """
        #if DEBUG
        import Combine
        #endif

        @Injectable
        struct Service {}
        """)

        #expect(generated.contains("#if (DEBUG)\nimport Combine\n#endif"))
    }

    /// `import A.B` puts `A`'s contents in scope under `A`, so `A` is the name
    /// the generated file needs.
    @Test("a submodule import names its top-level module")
    func submoduleImportNamesItsModule() {
        let generated = CompileFixture.generate(source: """
        import Foundation.NSURL

        @Injectable
        struct Service {}
        """)

        #expect(generated.contains("\nimport Foundation"))
    }

    // MARK: - Two modules, one name

    /// Copying imports means two modules exporting one name can both be in scope
    /// in the generated file, where neither source file had the clash. Writing
    /// the module out is how that is resolved in ordinary Swift, and Zerk has to
    /// honour it: the qualifier is normally stripped, since `Core.Foo` and `Foo`
    /// are one type — but stripping *these* would merge two types that are not.
    @Test("two modules producing one name stay two keys")
    func clashingQualifiersAreNotMerged() {
        let result = CompileFixture.generateWithResolution(source: """
        import ModuleA
        import ModuleB

        @Injectable<ModuleA.Config>
        struct LiveA: ModuleA.Config {
            @InjectableProviding
            init() {}
        }

        @Injectable<ModuleB.Config>
        struct LiveB: ModuleB.Config {
            @InjectableProviding
            init() {}
        }
        """)

        // Not "Multiple types are injectable under 'Config'": they are two keys.
        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
        #expect(result.output.output.contains("extension Zerk<ModuleA.Config> {"))
        #expect(result.output.output.contains("extension Zerk<ModuleB.Config> {"))
    }

    /// And with no clash the qualifier is still dropped, so a dependency written
    /// `Core.Serving` resolves against a provider registered as `Serving`.
    @Test("a lone qualifier is still stripped")
    func loneQualifierIsStillStripped() {
        let result = CompileFixture.generateWithResolution(source: """
        import Core

        @Injectable<Core.Serving>
        struct Live: Core.Serving {
            @InjectableProviding
            init() {}
        }

        @Injectable
        struct Consumer {
            let api: Core.Serving
        }
        """)

        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
        #expect(result.output.output.contains("extension Zerk<Serving> {"))
        #expect(result.output.output.contains("api: Core.Serving = Zerk<Core.Serving>.inject()"))
    }
}
