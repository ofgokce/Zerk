//
//  IsolationCompileTests.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 28.07.2026.
//

import Testing
@testable import CodegenToolkit

/// SE-0411 ("Isolated default value expressions") is the load-bearing
/// assumption of the whole isolation model: it makes a default argument
/// evaluate in the *callee's* isolation domain, so an isolated default is legal
/// exactly when the member shares that isolation.
///
/// If case 2 below ever regresses, the S partition collapses into A — every
/// member with a resolvable dependency would have to split, and isolation would
/// have to move into member bodies alongside effects.
@Suite("SE-0411 regression")
struct SE0411RegressionTests {

    private static let fixture = """
    class A {}
    class B { init(a: A) {} }
    class C { init(b: B) {} }

    enum SE0411 {
        nonisolated static var a: A { A() }

        // 1. nonisolated default, isolated member — must compile.
        @MainActor static func b(a: A = SE0411.a) -> B { B(a: a) }

        // 2. isolated default, member in the same domain — must compile.
        //    This is the case the E/S partition depends on.
        @MainActor static func c(b: B = SE0411.b()) -> C { C(b: b) }
    }
    """

    private static let crossDomainFixture = """
    class A {}
    class B { init(a: A) {} }
    class C { init(b: B) {} }

    enum SE0411 {
        nonisolated static var a: A { A() }
        @MainActor static func b(a: A = SE0411.a) -> B { B(a: a) }

        // 3. isolated default, nonisolated member — must NOT compile.
        nonisolated static func c(b: B = SE0411.b()) -> C { C(b: b) }
    }
    """

    @Test("isolated default arguments compile when the member shares the domain")
    func isolatedDefaultsCompileInSameDomain() throws {
        let result = try CompileFixture.run(
            source: Self.fixture,
            options: .swift6(defaultIsolation: nil)
        )
        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(result.didCompile, Comment(rawValue: result.compilerOutput))
    }

    @Test("isolated default arguments are rejected in a nonisolated member")
    func isolatedDefaultsRejectedInNonisolatedMember() throws {
        let result = try CompileFixture.run(
            source: Self.crossDomainFixture,
            options: .swift6(defaultIsolation: nil)
        )
        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(!result.didCompile)
    }

    @Test("isolated default arguments do not compile in stock Swift 5 language mode")
    func isolatedDefaultsRejectedInSwift5() throws {
        let result = try CompileFixture.run(
            source: Self.fixture,
            options: .swift5(defaultIsolation: nil)
        )
        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        // Without an opt-in, Swift 5 evaluates default arguments at the caller,
        // so even the same-domain case fails. This is the *only* construct Zerk
        // refuses under Swift 5 — see `supportsIsolatedDefaultValues`.
        #expect(!result.didCompile)
    }

    @Test("the IsolatedDefaultValues upcoming feature unlocks Swift 5")
    func isolatedDefaultsCompileInSwift5WithUpcomingFeature() throws {
        let result = try CompileFixture.run(
            source: Self.fixture,
            options: .swift5(defaultIsolation: nil, unlock: .upcomingFeature)
        )
        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(result.didCompile, Comment(rawValue: result.compilerOutput))
    }

    @Test("complete strict concurrency unlocks Swift 5")
    func isolatedDefaultsCompileInSwift5WithCompleteConcurrency() throws {
        let result = try CompileFixture.run(
            source: Self.fixture,
            options: .swift5(defaultIsolation: nil, unlock: .completeConcurrency)
        )
        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(result.didCompile, Comment(rawValue: result.compilerOutput))
    }
}

/// A Swift 5 language mode target under a Swift 6 toolchain — an app that has
/// not flipped `SWIFT_VERSION` yet — is the common case, not an exotic one.
///
/// Only one construct Zerk emits depends on SE-0411: a default argument whose
/// resolved expression is isolated to the *same* global actor as the member. A
/// global actor appearing anywhere else in the graph is irrelevant, so the
/// refusal must not key on "this module mentions a global actor".
@Suite("Swift 5 language mode")
struct Swift5LanguageModeTests {

    /// `@MainActor` member, nonisolated dependency. The default argument is a
    /// nonisolated expression, which SE-0411 does not govern.
    private static let isolatedMemberNonisolatedDependency = """
    protocol Storing {}
    protocol Caching {}

    @Injectable<Storing>
    final class Store: Storing {
        init() {}
    }

    @MainActor
    @Injectable<Caching>
    final class UICache: Caching {
        init(store: Storing) {}
    }
    """

    /// `@MainActor` member, `@MainActor` dependency: the SE-0411 construct.
    private static let sameDomainIsolated = """
    protocol Storing {}
    protocol Caching {}

    @MainActor
    @Injectable<Storing>
    final class UIStore: Storing {
        init() {}
    }

    @MainActor
    @Injectable<Caching>
    final class UICache: Caching {
        init(store: Storing) {}
    }
    """

    @Test("an isolated member with a nonisolated dependency is not an SE-0411 construct")
    func isolatedMemberWithNonisolatedDependencyIsNotFlagged() {
        var settings = ZerkSettings.default
        settings.swiftVersion = "5"

        let output = CompileFixture.generateOutput(
            source: Self.isolatedMemberNonisolatedDependency,
            settings: settings
        )

        #expect(output.output.contains("@MainActor static func uICache(store: Storing = Zerk<Storing>.inject())"))
        #expect(!output.usesIsolatedDefaultArguments)
    }

    @Test("an isolated member with a same-domain isolated dependency is flagged")
    func sameDomainIsolatedDependencyIsFlagged() {
        var settings = ZerkSettings.default
        settings.swiftVersion = "5"

        let output = CompileFixture.generateOutput(
            source: Self.sameDomainIsolated,
            settings: settings
        )

        #expect(output.usesIsolatedDefaultArguments)
    }

    @Test("a cross-domain graph is not an SE-0411 construct")
    func crossDomainGraphIsNotFlagged() {
        let source = """
        protocol Logging {}
        protocol Reporting {}

        @MainActor
        @Injectable<Logging>
        final class Logger: Logging {
            init() {}
        }

        @Injectable<Reporting>
        final class Reporter: Reporting {
            nonisolated init(logger: Logging) {}
        }
        """

        // Crossing a domain forces resolution into the body behind `await`,
        // which is not a default argument at all.
        #expect(!CompileFixture.generateOutput(source: source).usesIsolatedDefaultArguments)
    }

    @Test("an isolated member with a nonisolated dependency compiles under stock Swift 5")
    func isolatedMemberWithNonisolatedDependencyCompilesInSwift5() throws {
        let result = try CompileFixture.run(
            source: Self.isolatedMemberNonisolatedDependency,
            options: .swift5(defaultIsolation: nil)
        )
        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(result.didCompile, Comment(rawValue: result.compilerOutput + "\n\n" + result.generated))
    }

    @Test("a same-domain isolated graph compiles under Swift 5 once unlocked",
          arguments: [CompileFixture.SE0411Unlock.upcomingFeature, .completeConcurrency])
    func sameDomainIsolatedGraphCompilesWhenUnlocked(unlock: CompileFixture.SE0411Unlock) throws {
        let result = try CompileFixture.run(
            source: Self.sameDomainIsolated,
            options: .swift5(defaultIsolation: nil, unlock: unlock)
        )
        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(result.didCompile, Comment(rawValue: result.compilerOutput + "\n\n" + result.generated))
    }

    @Test("either opt-in satisfies the capability, and stock Swift 5 does not")
    func capabilityPredicateReflectsBothUnlocks() {
        var stock = ZerkSettings.default
        stock.swiftVersion = "5"
        #expect(!stock.supportsIsolatedDefaultValues)

        var targeted = stock
        targeted.strictConcurrency = .targeted
        #expect(!targeted.supportsIsolatedDefaultValues)

        var feature = stock
        feature.isolatedDefaultValues = true
        #expect(feature.supportsIsolatedDefaultValues)

        var complete = stock
        complete.strictConcurrency = .complete
        #expect(complete.supportsIsolatedDefaultValues)

        // Swift 6 language mode has it unconditionally.
        #expect(ZerkSettings.default.supportsIsolatedDefaultValues)
    }
}

@Suite("Generated code compiles")
struct GeneratedCodeCompileTests {

    @Test("a nonisolated graph type-checks")
    func nonisolatedGraphCompiles() throws {
        let source = """
        protocol Logging {}
        protocol Reporting {}

        @Injectable<Logging>
        final class Logger: Logging {
            init() {}
        }

        @Injectable<Reporting>
        final class Reporter: Reporting {
            init(logger: Logging) {}
        }
        """

        let result = try CompileFixture.run(source: source, options: .swift6(defaultIsolation: nil))
        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(result.didCompile, Comment(rawValue: result.compilerOutput + "\n\n" + result.generated))
    }

    @Test("a MainActor graph type-checks")
    func mainActorGraphCompiles() throws {
        let source = """
        protocol Logging {}
        protocol Reporting {}

        @MainActor
        @Injectable<Logging>
        final class Logger: Logging {
            init() {}
        }

        @MainActor
        @Injectable<Reporting>
        final class Reporter: Reporting {
            init(logger: Logging) {}
        }
        """

        let result = try CompileFixture.run(source: source, options: .swift6(defaultIsolation: nil))
        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(result.didCompile, Comment(rawValue: result.compilerOutput + "\n\n" + result.generated))
    }

    @Test("a nonisolated consumer of a MainActor provider type-checks")
    func crossDomainGraphCompiles() throws {
        let source = """
        protocol Logging {}
        protocol Reporting {}

        @MainActor
        @Injectable<Logging>
        final class Logger: Logging {
            init() {}
        }

        @Injectable<Reporting>
        final class Reporter: Reporting {
            nonisolated init(logger: Logging) {}
        }
        """

        let result = try CompileFixture.run(source: source, options: .swift6(defaultIsolation: nil))
        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(result.didCompile, Comment(rawValue: result.compilerOutput + "\n\n" + result.generated))
    }

    @Test("an actor injectable type-checks")
    func actorGraphCompiles() throws {
        let source = """
        protocol Storing: Sendable {}

        @Injectable<Storing>
        actor FileStore: Storing {
            init() {}
        }

        @Injectable
        final class Coordinator {
            init(store: Storing) {}
        }
        """

        let result = try CompileFixture.run(source: source, options: .swift6(defaultIsolation: nil))
        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(result.didCompile, Comment(rawValue: result.compilerOutput + "\n\n" + result.generated))
    }

    @Test("a graph under an ambient MainActor default type-checks")
    func ambientMainActorGraphCompiles() throws {
        let source = """
        protocol Logging {}
        protocol Reporting {}

        @Injectable<Logging>
        final class Logger: Logging {
            init() {}
        }

        @Injectable<Reporting>
        final class Reporter: Reporting {
            init(logger: Logging) {}
        }
        """

        let result = try CompileFixture.run(
            source: source,
            options: .swift6(defaultIsolation: "MainActor")
        )
        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(result.didCompile, Comment(rawValue: result.compilerOutput + "\n\n" + result.generated))
        // Everything is ambiently MainActor, so the registry is too — explicitly
        // rather than accidentally.
        #expect(result.generated.contains("@MainActor static var logger: Logging"))
    }

    @Test("an actor instance method with @injected type-checks")
    func actorInjectedInstanceMethodCompiles() throws {
        let source = """
        @Injectable
        struct Logger {
            init() {}
        }

        actor Worker {
            func run(@injected logger: Logger) {}
        }
        """

        let result = try CompileFixture.run(source: source, options: .swift6(defaultIsolation: nil))
        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(result.didCompile, Comment(rawValue: result.compilerOutput + "\n\n" + result.generated))
        #expect(result.generated.contains("extension Worker {\n    func run()"))
        #expect(!result.generated.contains("nonisolated func run()"))
    }

    @Test("an explicitly nonisolated actor method with @injected type-checks")
    func nonisolatedActorInjectedInstanceMethodCompiles() throws {
        let source = """
        @Injectable
        struct Logger {
            init() {}
        }

        actor Worker {
            nonisolated func run(@injected logger: Logger) {}
        }
        """

        let result = try CompileFixture.run(source: source, options: .swift6(defaultIsolation: nil))
        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(result.didCompile, Comment(rawValue: result.compilerOutput + "\n\n" + result.generated))
        #expect(result.generated.contains("nonisolated func run()"))
    }
}
