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

        @Injectable
        struct Stamp {
            @InjectableProviding
            init(at: Date, cancellable: AnyCancellable) {}
        }
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
        import Foundation

        @Injectable
        struct Service {
            @InjectableProviding
            init(at: Date) {}
        }
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
        struct Service {
            @InjectableProviding
            init(at: Date, cancellable: AnyCancellable) {}
        }
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
        struct Service {
            @InjectableProviding
            init(cancellable: AnyCancellable) {}
        }
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
        struct Service {
            @InjectableProviding
            init(url: NSURL) {}
        }
        """)

        #expect(generated.contains("\nimport Foundation"))
    }

    // MARK: - Only what is needed

    /// An import is copied from a file that put a name into the generated file
    /// which this module does not declare. A file registering nothing but local
    /// types has already been seen by the compiler here, so its imports buy the
    /// generated file nothing — and a module in scope for no reason is a name
    /// the generated file could trip over that it never needed.
    @Test("a file registering only local types contributes no imports")
    func localOnlyFilesContributeNothing() {
        let generated = CompileFixture.generate(source: """
        import Combine
        import Foundation

        protocol Repo {}

        @Injectable<Repo>
        struct LiveRepo: Repo {}
        """)

        #expect(!generated.contains("import Combine"))
        #expect(!generated.contains("import Foundation"))
        // `Zerk` is never optional.
        #expect(generated.contains("import Zerk"))
    }

    /// And one foreign name in the file is enough to bring them.
    @Test("one foreign name brings the file's imports")
    func oneForeignNameIsEnough() {
        let generated = CompileFixture.generate(source: """
        import Combine
        import Foundation

        protocol Repo {}

        @Injectable<Repo>
        struct LiveRepo: Repo {}

        @Injectable
        struct Stamp {
            @InjectableProviding
            init(at: Date) {}
        }
        """)

        #expect(generated.contains("\nimport Foundation"))
        // Both, because imports are read per file and this is one file. Narrowing
        // is per file rather than per name: which module a name came from is the
        // very thing syntax cannot tell.
        #expect(generated.contains("\nimport Combine"))
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

    /// The same clash between two *imported* keys, which is the shape it
    /// actually takes: a bare name two modules both produce is almost always
    /// foreign on both sides, so neither key is declared here. Read from
    /// `keyDisplayNames` alone this case was invisible, and the two imports
    /// merged into one key.
    @Test("two imported keys sharing a bare name stay two keys")
    func clashingImportedQualifiersAreNotMerged() {
        let result = CompileFixture.generateWithResolution(source: """
        import ModuleA
        import ModuleB

        enum ZerkImports {
            @ImportedInjectable
            static func a() -> ModuleA.Config

            @ImportedInjectable
            static func b() -> ModuleB.Config
        }

        @Injectable
        struct Bridge {
            @InjectableProviding
            init(a: ModuleA.Config, b: ModuleB.Config) {}
        }
        """)

        // Not "'Config' is imported more than once": they are two keys.
        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
        #expect(result.output.output.contains("a: ModuleA.Config = Zerk<ModuleA.Config>.inject()"))
        #expect(result.output.output.contains("b: ModuleB.Config = Zerk<ModuleB.Config>.inject()"))
    }

    /// A local declaration is a producer of a bare name too, and the one Swift
    /// picks: `Serving` names the local protocol and `Core.Serving` the
    /// imported one, which compiles as written. Stripping here merged them, and
    /// the report — that a key is both imported and declared locally — named
    /// the one thing the developer had done right.
    @Test("a local declaration shadows an imported name rather than merging with it")
    func aLocalDeclarationShadowsAnImportedName() {
        let result = CompileFixture.generateWithResolution(source: """
        import Core

        protocol Serving {}

        enum ZerkImports {
            @ImportedInjectable
            static func coreServing() -> Core.Serving
        }

        @Injectable<Serving>
        struct LocalServing: Serving {
            @InjectableProviding
            init() {}
        }

        @Injectable
        struct Feed {
            @InjectableProviding
            init(local: Serving, foreign: Core.Serving) {}
        }
        """)

        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
        #expect(result.output.output.contains("local: Serving = Zerk<Serving>.inject()"))
        #expect(result.output.output.contains("foreign: Core.Serving = Zerk<Core.Serving>.inject()"))
    }

    /// The nested form of the same shadow. `Core.Outer.Inner` and `Outer.Inner`
    /// are two types once this module declares `Outer`, so the qualifier stays
    /// — decided on the first component, which is the one Swift looks up.
    @Test("a local nested type shadows an imported one of the same spelling")
    func aLocalNestedTypeShadowsAnImportedOne() {
        let result = CompileFixture.generateWithResolution(source: """
        import Core

        enum Outer {
            protocol Inner {}
        }

        enum ZerkImports {
            @ImportedInjectable
            static func coreInner() -> Core.Outer.Inner
        }

        @Injectable<Outer.Inner>
        struct LocalInner: Outer.Inner {
            @InjectableProviding
            init() {}
        }

        @Injectable
        struct Feed {
            @InjectableProviding
            init(local: Outer.Inner, foreign: Core.Outer.Inner) {}
        }
        """)

        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
        #expect(result.output.output.contains("local: Outer.Inner = Zerk<Outer.Inner>.inject()"))
        #expect(result.output.output.contains("foreign: Core.Outer.Inner = Zerk<Core.Outer.Inner>.inject()"))
    }

    /// A qualifier is only a module name while no local type claims the word.
    /// Declaring `Core` shadows the module everywhere in this one — including
    /// files that do not declare it — so `Core.Serving` names that type's own
    /// member, and stripping it would emit `extension Zerk<Serving>` over
    /// whatever the *import* calls `Serving`, while the call site still said
    /// `Zerk<Core.Serving>`. The import is still emitted; only stripping stops.
    @Test("a type named after a module is not a module qualifier")
    func aModuleNamesakeIsNotAQualifier() {
        let result = CompileFixture.generateWithResolution(source: """
        import Core

        enum Core {
            protocol Serving {}
        }

        @Injectable<Core.Serving>
        struct LocalNested: Core.Serving {
            @InjectableProviding
            init() {}
        }

        @Injectable
        struct Feed {
            @InjectableProviding
            init(nested: Core.Serving) {}
        }

        @Injectable
        struct Wall {
            @InjectableProviding
            init(token: Core.Token) {}
        }
        """)

        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
        #expect(result.output.output.contains("extension Zerk<Core.Serving> {"))
        #expect(result.output.output.contains("nested: Core.Serving = Zerk<Core.Serving>.inject()"))
        #expect(!result.output.output.contains("extension Zerk<Serving> {"))
    }

    // MARK: - Nested scope

    /// Swift looks a bare name up innermost-first; Zerk re-emits it at file
    /// scope. Written inside `LiveFeed`, `Config` is `LiveFeed.Config`, and the
    /// generated file said `config: Config` — which compiles as
    /// `cannot find type 'Config' in scope`, against code nobody wrote.
    @Test("a dependency naming a type nested in its own scope is qualified")
    func aNestedDependencyNameIsQualified() {
        let result = CompileFixture.generateWithResolution(source: """
        @Injectable<Feed>
        struct LiveFeed: Feed {
            struct Config {}

            @InjectableProviding
            init(config: Config) {}
        }
        """)

        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
        #expect(result.output.output.contains("config: LiveFeed.Config"))
        #expect(!result.output.output.contains("config: Config"))
    }

    /// Writing the qualified spelling yourself reaches the same place, so the
    /// rewrite adds a spelling rather than requiring one.
    @Test("a dependency already qualified is left alone")
    func anAlreadyQualifiedDependencyIsUnchanged() {
        let result = CompileFixture.generateWithResolution(source: """
        @Injectable<Feed>
        struct LiveFeed: Feed {
            struct Config {}

            @InjectableProviding
            init(config: LiveFeed.Config) {}
        }
        """)

        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
        #expect(result.output.output.contains("config: LiveFeed.Config"))
    }

    /// Nesting inside the name too: Swift resolves the *base* of a dotted path
    /// in the enclosing scope, so `Config.Key` is `LiveFeed.Config.Key` and the
    /// `Key` after the dot is not touched.
    @Test("only the base of a dotted spelling is qualified")
    func onlyTheBaseOfADottedSpellingIsQualified() {
        let result = CompileFixture.generateWithResolution(source: """
        @Injectable<Feed>
        struct LiveFeed: Feed {
            struct Config { struct Key {} }

            @InjectableProviding
            init(key: Config.Key) {}
        }
        """)

        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
        #expect(result.output.output.contains("key: LiveFeed.Config.Key"))
    }

    /// The same lookup through `@Injected`, where the damage was a *wrong*
    /// answer rather than a missing one: the bare `Service` matched the
    /// top-level key, whose provider is async, and Zerk refused code that was
    /// resolving the synchronous `Feature.Service` all along.
    @Test("an @Injected use is read in the scope it was written in")
    func anInjectedUseIsReadInItsOwnScope() {
        let result = CompileFixture.generateWithResolution(source: """
        protocol Service {}

        @Injectable<Service>
        struct SlowService: Service {
            @InjectableProviding
            init() async {}
        }

        enum Feature {
            protocol Service {}

            final class ViewModel {
                @Injected var service: Service
            }
        }

        @Injectable<Feature.Service>
        struct FastService: Feature.Service {
            @InjectableProviding
            init() {}
        }
        """)

        // Not "'Service' has an async ... chain", which read the wrong key.
        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
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
