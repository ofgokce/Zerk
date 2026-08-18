//
//  ConditionalCompilationTests.swift
//  Zerk
//

import Testing
@testable import CodegenToolkit

/// Coverage of `#if` around Zerk declarations.
///
/// Zerk never evaluates a condition — it cannot, and
/// ``CompilationCondition`` says why — so what is under test is that the guard
/// *travels*: a registration written inside `#if DEBUG` generates code inside
/// `#if DEBUG`, and registrations in different clauses of one `#if` stop
/// competing for their key.
///
/// The claim "the guard landed on the right declaration" is not something a
/// golden string can settle on its own: a file can contain exactly the expected
/// text and still fail to build in one configuration. So the load-bearing cases
/// go through `swiftc` **twice**, once with the condition set and once without,
/// and both have to compile.
@Suite("Conditional compilation")
struct ConditionalCompilationTests {

    /// The shape from the bug report: one key, a different implementation per
    /// configuration, both marked primary.
    static let debugReleaseSwap = """
    protocol Service {}
    protocol Logging {}

    @Injectable<Logging>
    struct Logger: Logging {}

    #if DEBUG
    @Injectable<Service>(primary: true)
    struct DebugService: Service {
        let logging: Logging
    }
    #else
    @Injectable<Service>(primary: true)
    struct ReleaseService: Service {
        let logging: Logging
    }
    #endif

    @Injectable
    struct App {
        let service: Service
    }
    """

    // MARK: - The swap

    @Test("branches of one #if do not compete for a key")
    func exclusiveBranchesBothWin() {
        let result = CompileFixture.generateWithResolution(source: Self.debugReleaseSwap)

        // Neither "multiple primary injectables" nor "none is primary": the two
        // registrations are alternatives, not rivals.
        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")

        // One `inject()` per configuration, each under its own guard.
        #expect(result.output.output.contains("""
        #if (DEBUG)
            nonisolated static func inject() -> Service {
                debugService()
            }
        #endif
        """))
        #expect(result.output.output.contains("""
        #if !(DEBUG)
            nonisolated static func inject() -> Service {
                releaseService()
            }
        #endif
        """))
    }

    @Test("the swap compiles in both configurations", arguments: [true, false])
    func swapCompilesEitherWay(isDebug: Bool) throws {
        let result = try CompileFixture.run(
            source: Self.debugReleaseSwap,
            options: isDebug ? .swift6(defining: "DEBUG") : .swift6
        )
        try #require(!result.skipped)
        #expect(result.didCompile, "\(result.compilerOutput)\n\(result.generated)")
    }

    @Test("the key's consumers resolve it the same way in both branches")
    func consumersAreUnguarded() {
        let generated = CompileFixture.generate(source: Self.debugReleaseSwap)

        // `App` is unconditional, so its member is too — and it resolves the key
        // through the one call that exists in every configuration.
        #expect(generated.contains(
            "nonisolated static func app(service: Service = Zerk<Service>.inject()) -> App {"))
    }

    // MARK: - A key that exists in one configuration only

    /// The other half of the bug: a lone `#if DEBUG` registration used to emit
    /// `return DebugOnly()` unconditionally, so a Release build named a type that
    /// was not there.
    @Test("a key registered in one branch guards its whole extension")
    func loneBranchGuardsTheExtension() throws {
        let source = """
        #if DEBUG
        @Injectable
        struct DebugOnly {}
        #endif
        """

        let generated = CompileFixture.generate(source: source)

        // The extension header names the type, so the guard has to be outside
        // it — inside, the header itself would not compile in Release.
        #expect(generated.contains("""
        #if (DEBUG)
        extension Zerk<DebugOnly> {
        """))
        #expect(generated.contains("""
        #if (DEBUG)
        extension Zerk<DebugOnly>.Interjection {
            nonisolated var `debugOnly`: Void {}
        }
        #endif
        """))

        for options in [CompileFixture.Options.swift6(defining: "DEBUG"), .swift6] {
            let result = try CompileFixture.run(source: source, options: options)
            try #require(!result.skipped)
            #expect(result.didCompile, "\(result.compilerOutput)\n\(result.generated)")
        }
    }

    @Test("an unconditional module is generated exactly as before")
    func nothingChangesWithoutAnIf() {
        let generated = CompileFixture.generate(source: """
        @Injectable
        struct Service {}
        """)

        #expect(!generated.contains("#if"))
        #expect(!generated.contains("#endif"))
    }

    // MARK: - Composing conditions

    @Test("nested #ifs become one conjunction")
    func nestedConditionsCombine() {
        let generated = CompileFixture.generate(source: """
        #if DEBUG
        #if os(iOS)
        @Injectable
        struct Probe {}
        #endif
        #endif
        """)

        #expect(generated.contains("#if (DEBUG) && (os(iOS))"))
    }

    /// An `#elseif` is only reached when every earlier condition failed, so its
    /// guard has to carry those failures. Emitting the bare condition would
    /// widen the clause to configurations the developer excluded.
    @Test("#elseif carries the earlier conditions negated")
    func elseIfNegatesWhatCameBefore() {
        let generated = CompileFixture.generate(source: """
        protocol Service {}

        #if DEBUG
        @Injectable<Service>(primary: true)
        struct DebugService: Service {}
        #elseif BETA
        @Injectable<Service>(primary: true)
        struct BetaService: Service {}
        #else
        @Injectable<Service>(primary: true)
        struct ReleaseService: Service {}
        #endif
        """)

        #expect(generated.contains("#if !(DEBUG) && (BETA)"))
        #expect(generated.contains("#if !(DEBUG) && !(BETA)"))
    }

    @Test("a three-way swap compiles in every configuration",
          arguments: [[String](), ["DEBUG"], ["BETA"]])
    func threeWaySwapCompiles(conditions: [String]) throws {
        let source = """
        protocol Service {}

        #if DEBUG
        @Injectable<Service>(primary: true)
        struct DebugService: Service {}
        #elseif BETA
        @Injectable<Service>(primary: true)
        struct BetaService: Service {}
        #else
        @Injectable<Service>(primary: true)
        struct ReleaseService: Service {}
        #endif

        @Injectable
        struct App {
            let service: Service
        }
        """

        var options = CompileFixture.Options.swift6
        options.extraFlags = conditions.map { "-D\($0)" }
        let result = try CompileFixture.run(source: source, options: options)
        try #require(!result.skipped)
        #expect(result.didCompile, "\(result.compilerOutput)\n\(result.generated)")
    }

    // MARK: - Everything else the guard has to reach

    @Test("a conditional value guards its member")
    func conditionalValue() throws {
        let source = """
        #if DEBUG
        @InjectableValue
        var apiHost: String { "debug.example.com" }
        #endif
        """

        let generated = CompileFixture.generate(source: source)
        #expect(generated.contains("""
        #if (DEBUG)
        extension Zerk<String> {
        """))

        let result = try CompileFixture.run(source: source)
        try #require(!result.skipped)
        #expect(result.didCompile, "\(result.compilerOutput)\n\(result.generated)")
    }

    @Test("a conditional singleton guards its storage slot")
    func conditionalSingletonStorage() throws {
        let source = """
        #if DEBUG
        @Singleton
        @Injectable
        final class Cache: @unchecked Sendable {}
        #endif
        """

        let generated = CompileFixture.generate(source: source)

        // The slot names the type, so it cannot outlive it — but the enclosing
        // namespace is emitted either way, since an empty one is harmless and
        // wrapping it would take a second guard.
        #expect(generated.contains("""
        private enum _$zerk_singletons {
        #if (DEBUG)
            nonisolated(unsafe) static let cache: Cache = Cache()
        #endif
        }
        """))

        for options in [CompileFixture.Options.swift6(defining: "DEBUG"), .swift6] {
            let result = try CompileFixture.run(source: source, options: options)
            try #require(!result.skipped)
            #expect(result.didCompile, "\(result.compilerOutput)\n\(result.generated)")
        }
    }

    @Test("a conditional @injected initializer guards its overload")
    func conditionalMarkedMember() throws {
        let source = """
        protocol Logging {}

        @Injectable<Logging>
        struct Logger: Logging {}

        #if DEBUG
        struct Probe {
            init(@injected logging: Logging) {}
        }
        #endif
        """

        let generated = CompileFixture.generate(source: source)
        #expect(generated.contains("""
        #if (DEBUG)
        extension Probe {
        """))

        for options in [CompileFixture.Options.swift6(defining: "DEBUG"), .swift6] {
            let result = try CompileFixture.run(source: source, options: options)
            try #require(!result.skipped)
            #expect(result.didCompile, "\(result.compilerOutput)\n\(result.generated)")
        }
    }

    @Test("a conditional #ZerkImport guards its import")
    func conditionalImport() {
        let generated = CompileFixture.generate(source: """
        #if canImport(UIKit)
        #ZerkImport(module: "UIKit")
        #endif
        """)

        #expect(generated.contains("""
        #if (canImport(UIKit))
        import UIKit
        #endif
        """))
    }

    /// An unconditional ask is already correct everywhere a conditional one
    /// would have been, so it wins rather than being narrowed.
    @Test("a module asked for both ways is imported unconditionally")
    func widerImportWins() {
        let generated = CompileFixture.generate(source: """
        #ZerkImport(module: "Foundation")

        #if DEBUG
        #ZerkImport(module: "Foundation")
        #endif
        """)

        #expect(generated.contains("import Foundation"))
        #expect(!generated.contains("#if (DEBUG)\nimport Foundation"))
    }

    /// Asking twice under the same guard must keep the guard.
    ///
    /// Two `#if DEBUG` blocks are two conditions — clause identity is file and
    /// offset — and the second ask used to widen the import to unconditional
    /// because it was not *equal* to the first. Writing the same guarded
    /// `#ZerkImport` in each file that needs the module is an ordinary way to
    /// work, and it silently produced a Release build importing a module that is
    /// not in it.
    @Test("a module asked for twice under the same guard keeps it")
    func repeatedImportKeepsItsGuard() {
        let generated = CompileFixture.generate(source: """
        #if DEBUG
        #ZerkImport(module: "Foundation")
        #endif

        #if DEBUG
        #ZerkImport(module: "Foundation")
        #endif
        """)

        #expect(generated.contains("#if (DEBUG)\nimport Foundation\n#endif"))
        // Once, not twice: one guard, however many asks wrote it.
        #expect(generated.components(separatedBy: "import Foundation").count == 2,
                Comment(rawValue: generated))
    }

    /// Genuinely different guards each keep their own, rather than collapsing to
    /// no guard at all. Swift accepts a module imported twice, so a build where
    /// both hold costs nothing — and a build where only one holds still gets it.
    @Test("a module asked for under two guards is imported under each")
    func differingImportsKeepBothGuards() {
        let generated = CompileFixture.generate(source: """
        #if DEBUG
        #ZerkImport(module: "Foundation")
        #endif

        #if os(iOS)
        #ZerkImport(module: "Foundation")
        #endif
        """)

        #expect(generated.contains("#if (DEBUG)\nimport Foundation\n#endif"))
        #expect(generated.contains("#if (os(iOS))\nimport Foundation\n#endif"))
    }

    // MARK: - What stops being a collision

    @Test("one member name in exclusive branches is not a redeclaration")
    func sameMemberNameInExclusiveBranches() throws {
        let source = """
        protocol Service {}

        #if DEBUG
        @Injectable<Service>(primary: true)
        struct Client: Service {}
        #else
        @Injectable<Service>(primary: true)
        struct Client: Service {}
        #endif
        """

        let result = CompileFixture.generateWithResolution(source: source)
        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")

        // One point, declared once per clause: the two members are different
        // members that happen to share a name.
        #expect(result.output.output.contains("""
        extension Zerk<Service>.Interjection {
        #if (DEBUG)
            nonisolated var `client`: Void {}
        #endif
        #if !(DEBUG)
            nonisolated var `client`: Void {}
        #endif
        }
        """))

        for options in [CompileFixture.Options.swift6(defining: "DEBUG"), .swift6] {
            let compiled = try CompileFixture.run(source: source, options: options)
            try #require(!compiled.skipped)
            #expect(compiled.didCompile, "\(compiled.compilerOutput)\n\(compiled.generated)")
        }
    }

    @Test("one value name in exclusive branches is not a duplicate")
    func sameValueNameInExclusiveBranches() {
        let result = CompileFixture.generateWithResolution(source: """
        #if DEBUG
        @InjectableValue
        var apiHost: String { "debug.example.com" }
        #else
        @InjectableValue
        var apiHost: String { "example.com" }
        #endif
        """)

        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
    }

    /// The limit of what Zerk claims to know. `#if DEBUG` and a *separate*
    /// `#if !DEBUG` are opposites to a reader, but telling so means evaluating
    /// `DEBUG` — so they are treated as able to coexist, and the ambiguity is
    /// reported rather than guessed at.
    @Test("two separate #ifs are not recognised as exclusive")
    func separateIfsStillCompete() {
        let result = CompileFixture.generateWithResolution(source: """
        protocol Service {}

        #if DEBUG
        @Injectable<Service>(primary: true)
        struct DebugService: Service {}
        #endif

        #if !DEBUG
        @Injectable<Service>(primary: true)
        struct ReleaseService: Service {}
        #endif
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error && $0.message.contains("Multiple primary injectables")
        }, "\(result.diagnostics.map(\.message))")
    }

    /// The election reads the same fact emission does, so a swap does not have
    /// to be written as one `#if` block.
    ///
    /// It used to partition candidates by block, which made these two rivals:
    /// the ambiguity was reported, and marking one of them primary — the fix the
    /// diagnostic asks for — was *accepted*, emitting an `inject()` guarded to
    /// the Debug configuration and called unconditionally from every consumer.
    /// That built in Debug and failed in Release, which is the worst place for a
    /// build to fail.
    @Test("a swap split over two blocks is elected per configuration")
    func separateBlocksOfOneSwapAreElectedApart() throws {
        let source = """
        protocol Service {}

        #if DEBUG
        @Injectable<Service>
        struct DebugService: Service {}
        #else
        struct ReleaseOnlyHelper {}
        #endif

        #if DEBUG
        struct DebugOnlyHelper {}
        #else
        @Injectable<Service>
        struct ReleaseService: Service {}
        #endif

        @Injectable
        struct Consumer {
            let service: Service
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        // No primary asked for: neither branch has a rival to be primary over.
        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")

        // One `inject()` per configuration, so no build is left without one.
        let generated = result.output.output
        #expect(generated.contains("#if (DEBUG)\n    nonisolated static func inject() -> Service {"))
        #expect(generated.contains("#if !(DEBUG)\n    nonisolated static func inject() -> Service {"))

        // And the pair actually holds up, in both configurations.
        for options in [CompileFixture.Options.swift6(defining: "DEBUG"),
                        CompileFixture.Options.swift6] {
            let compiled = try CompileFixture.run(source: source, options: options)
            try #require(!compiled.skipped)
            #expect(compiled.didCompile,
                    Comment(rawValue: "\(compiled.compilerOutput)\n\(compiled.generated)"))
        }
    }

    // MARK: - Refusals

    @Test("branches that resolve in different domains are refused")
    func mismatchedIsolationIsRefused() {
        let result = CompileFixture.generateWithResolution(source: """
        protocol Service {}

        #if DEBUG
        @Injectable<Service>(primary: true)
        struct DebugService: Service {}
        #else
        @MainActor
        @Injectable<Service>(primary: true)
        final class ReleaseService: Service {}
        #endif
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error
                && $0.message.contains("resolve in different isolation domains")
        }, "\(result.diagnostics.map(\.message))")
    }

    @Test("branches that resolve with different effects are refused")
    func mismatchedEffectsAreRefused() {
        let result = CompileFixture.generateWithResolution(source: """
        protocol Service {}

        struct DebugService: Service {}
        struct ReleaseService: Service {}

        #if DEBUG
        @Injectable<Service>(primary: true)
        func debugService() async -> Service { DebugService() }
        #else
        @Injectable<Service>(primary: true)
        func releaseService() -> Service { ReleaseService() }
        #endif
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error && $0.message.contains("resolve with different effects")
        }, "\(result.diagnostics.map(\.message))")
    }

    @Test("a #if gating an initializer is refused")
    func conditionalInitializerIsRefused() {
        let result = CompileFixture.generateWithResolution(source: """
        protocol Dep {}

        @Injectable
        struct Service {
            #if DEBUG
            init(dep: Dep) {}
            #else
            init() {}
            #endif
        }
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error && $0.message.contains("is read differently per configuration")
        }, "\(result.diagnostics.map(\.message))")
    }

    @Test("a #if gating an @InjectableProviding factory is refused")
    func conditionalProviderIsRefused() {
        let result = CompileFixture.generateWithResolution(source: """
        @Injectable
        struct Service {
            #if DEBUG
            @InjectableProviding
            static func make() -> Service { Service() }
            #endif
        }
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error && $0.message.contains("is read differently per configuration")
        }, "\(result.diagnostics.map(\.message))")
    }

    /// The refusal is narrow on purpose: most `#if`s inside a type have nothing
    /// to do with Zerk, and reporting those would be noise about code Zerk never
    /// reads.
    @Test("a #if inside a type that gates nothing Zerk reads is left alone")
    func harmlessConditionalMemberIsAccepted() {
        let result = CompileFixture.generateWithResolution(source: """
        @Injectable
        struct Service {
            init() {}

            #if DEBUG
            func debugHelper() {}
            #endif
        }
        """)

        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
        #expect(result.output.output.contains("nonisolated static var service: Service {"))
    }

    // MARK: - Resolving where nothing provides

    /// What satisfies a parameter, and whether Zerk can see that it is there in
    /// every configuration.
    ///
    /// A parameter is answered either by a key's providers or by one
    /// `@InjectableValue`, and *both* are emitted under their own `#if`. The
    /// first version of this check asked only about keys and skipped a
    /// value-satisfied parameter outright, so the whole defect survived on that
    /// path — which is why the two are one axis here rather than one suite each.
    struct Dependency {
        let name: String
        /// What provides it.
        let declarations: String
        /// Anything the declarations need in scope.
        let preamble: String
        let parameterName: String
        let parameterType: String
        /// Whether Zerk can prove the declarations cover every configuration.
        let isCovering: Bool
        /// `@Injected` names a type, and a value is matched by name as well as
        /// key — so a value is unreachable that way, and the cell is skipped
        /// rather than asserted about.
        let isReachableByInjectedProperty: Bool

        static let key = "protocol Service {}"

        static let all: [Dependency] = [
            Dependency(name: "key, unconditional",
                       declarations: """
                       @Injectable<Service>
                       struct LiveService: Service {}
                       """,
                       preamble: key, parameterName: "service", parameterType: "Service",
                       isCovering: true, isReachableByInjectedProperty: true),
            Dependency(name: "key, #if with #else",
                       declarations: """
                       #if DEBUG
                       @Injectable<Service>
                       struct DebugService: Service {}
                       #else
                       @Injectable<Service>
                       struct ReleaseService: Service {}
                       #endif
                       """,
                       preamble: key, parameterName: "service", parameterType: "Service",
                       isCovering: true, isReachableByInjectedProperty: true),
            // Covering without being one block: the second clause is reached
            // only because `DEBUG` failed, which is the fact `contradicts` reads.
            Dependency(name: "key, two blocks",
                       declarations: """
                       #if DEBUG
                       @Injectable<Service>
                       struct DebugService: Service {}
                       #endif

                       #if DEBUG
                       #else
                       @Injectable<Service>
                       struct ReleaseService: Service {}
                       #endif
                       """,
                       preamble: key, parameterName: "service", parameterType: "Service",
                       isCovering: true, isReachableByInjectedProperty: true),
            Dependency(name: "key, #if alone",
                       declarations: """
                       #if DEBUG
                       @Injectable<Service>
                       struct DebugService: Service {}
                       #endif
                       """,
                       preamble: key, parameterName: "service", parameterType: "Service",
                       isCovering: false, isReachableByInjectedProperty: true),
            // Opposites to a reader; two independent conditions to Zerk, which
            // does not read a negation. Reported rather than assumed — the
            // documented direction to err in.
            Dependency(name: "key, #if and a separate negation",
                       declarations: """
                       #if DEBUG
                       @Injectable<Service>(primary: true)
                       struct DebugService: Service {}
                       #endif

                       #if !DEBUG
                       @Injectable<Service>
                       struct ReleaseService: Service {}
                       #endif
                       """,
                       preamble: key, parameterName: "service", parameterType: "Service",
                       isCovering: false, isReachableByInjectedProperty: true),
            Dependency(name: "value, unconditional",
                       declarations: "@InjectableValue var retries: Int { 3 }",
                       preamble: "", parameterName: "retries", parameterType: "Int",
                       isCovering: true, isReachableByInjectedProperty: false),
            Dependency(name: "value, #if alone",
                       declarations: """
                       #if DEBUG
                       @InjectableValue var retries: Int { 3 }
                       #endif
                       """,
                       preamble: "", parameterName: "retries", parameterType: "Int",
                       isCovering: false, isReachableByInjectedProperty: false),
            Dependency(name: "referenced value, #if alone",
                       declarations: """
                       #if DEBUG
                       @InjectableValue(.referenced) var retries: Int { 3 }
                       #endif
                       """,
                       preamble: "", parameterName: "retries", parameterType: "Int",
                       isCovering: false, isReachableByInjectedProperty: false),
        ]
    }

    /// One way of consuming a dependency.
    ///
    /// Every one of them writes a resolution guarded by whatever guards the
    /// *declaration*, while the member behind it is guarded by whatever guards
    /// what provides it. Nothing compared the two, so a dependency registered
    /// under `#if DEBUG` and injected without a guard emitted a call to a member
    /// a Release build does not contain — and it failed inside
    /// `Zerk.generated.swift`, in the configuration nobody builds while writing
    /// the code.
    struct Consumption {
        let name: String
        let declaration: (Dependency) -> String
        /// Whether this path can reach a value at all.
        let reachesValues: Bool

        static let all: [Consumption] = [
            Consumption(name: "provider dependency", declaration: { dependency in
                """
                @Injectable
                struct Consumer {
                    let \(dependency.parameterName): \(dependency.parameterType)
                }
                """
            }, reachesValues: true),
            Consumption(name: "@injected overload", declaration: { dependency in
                """
                final class Screen {
                    init(@injected \(dependency.parameterName): \(dependency.parameterType),
                         title: String) {}
                }
                """
            }, reachesValues: true),
            // The macro writes the call into the developer's own file, so it is
            // guarded by the declaration exactly as the other two are.
            Consumption(name: "@Injected property", declaration: { dependency in
                """
                final class Screen {
                    @Injected var \(dependency.parameterName): \(dependency.parameterType)
                }
                """
            }, reachesValues: false),
        ]
    }

    @Test("a dependency is refused where it is injected but not provided",
          arguments: Consumption.all, Dependency.all)
    func injectingWhereNothingProvides(consumption: Consumption,
                                       dependency: Dependency) {
        guard consumption.reachesValues || dependency.isReachableByInjectedProperty else {
            return
        }

        let result = CompileFixture.generateWithResolution(source: """
        \(dependency.preamble)

        \(dependency.declarations)

        \(consumption.declaration(dependency))
        """)

        let gaps = result.diagnostics.filter {
            $0.severity == .error && $0.message.contains("Nothing provides")
        }
        if dependency.isCovering {
            #expect(gaps.isEmpty, "\(consumption.name)/\(dependency.name): \(gaps.map(\.message))")
        } else {
            #expect(gaps.count == 1,
                    "\(consumption.name)/\(dependency.name): \(result.diagnostics.map(\.message))")
            // Named, because "somewhere" would leave the developer to work out
            // which configuration is missing it.
            #expect(gaps.first?.message.contains("a build where DEBUG is false") == true,
                    "\(gaps.map(\.message))")
        }
    }

    /// A consumer guarded the way its provider is is not a gap, and that holds
    /// across separate `#if` blocks — the same condition text is the same
    /// condition, whichever block wrote it.
    @Test("a consumer under the provider's own guard is accepted",
          arguments: Consumption.all, Dependency.all)
    func guardedConsumerIsAccepted(consumption: Consumption, dependency: Dependency) {
        guard !dependency.isCovering,
              consumption.reachesValues || dependency.isReachableByInjectedProperty else {
            return
        }

        let result = CompileFixture.generateWithResolution(source: """
        \(dependency.preamble)

        \(dependency.declarations)

        #if DEBUG
        \(consumption.declaration(dependency))
        #endif
        """)

        let gaps = result.diagnostics.filter {
            $0.severity == .error && $0.message.contains("Nothing provides")
        }
        #expect(gaps.isEmpty, "\(consumption.name)/\(dependency.name): \(gaps.map(\.message))")
    }

    // MARK: - The graph

    @Test("the graph records the guard each provider is emitted under")
    func graphRecordsConditions() throws {
        let graph = CompileFixture.graph(source: Self.debugReleaseSwap)

        let service = try #require(graph.keys.first { $0.key == "Service" })
        #expect(service.providers.map(\.condition).sorted { ($0 ?? "") < ($1 ?? "") }
                == ["!(DEBUG)", "(DEBUG)"])

        let app = try #require(graph.keys.first { $0.key == "App" })
        #expect(app.providers.allSatisfy { $0.condition == nil })
    }
}

extension ConditionalCompilationTests.Consumption: CustomTestStringConvertible {
    var testDescription: String { name }
}

extension ConditionalCompilationTests.Dependency: CustomTestStringConvertible {
    var testDescription: String { name }
}
