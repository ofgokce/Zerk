//
//  ScopedTests.swift
//  Zerk
//

import Testing
@testable import CodegenToolkit

/// Coverage of `@Scoped`: one instance kept per named scope, dropped when that
/// scope is reset.
///
/// The shape under test is `_$zerk_scoped` — a `ZerkScopedBox` per type, read
/// through a per-key getter that hands the box a construction closure. Two
/// things about that arrangement are easy to get wrong and invisible in a golden
/// string, so they go through `swiftc`: the box slot's isolation, which
/// `SWIFT_DEFAULT_ACTOR_ISOLATION` can silently change, and the closure, which
/// runs in the *member's* domain rather than the box's.
@Suite("Scoped injectables")
struct ScopedTests {

    /// Every fixture needs a scope to name. Declared `nonisolated` for the
    /// reason the generated file's own comment gives: under an ambient
    /// global-actor default an unannotated `static let` becomes isolated, and a
    /// nonisolated box slot could not then read it.
    static let scopeDeclarations = """
    extension InjectionScope {
        nonisolated static let session = InjectionScope("session")
        nonisolated static let checkout = InjectionScope("checkout")
    }
    """

    // MARK: - The emitted shape

    @Test("a scoped type reads its instance through a box, built at the member")
    func emitsBoxAndMemberConstruction() {
        let source = """
        \(Self.scopeDeclarations)

        protocol Caching: AnyObject {}

        @Scoped(.session)
        @Injectable<Caching>
        final class SessionCache: Caching {}
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("private enum _$zerk_scoped {"))
        #expect(result.output.output.contains(
            "nonisolated static let sessionCache = ZerkScopedBox<SessionCache>(scope: .session)"))

        // The construction is at the member, not in the box.
        #expect(result.output.output.contains(
            "return _$zerk_scoped.sessionCache.value { SessionCache() }"))

        // A kept instance is read, never called — so no factory function and no
        // `inject()` that calls one.
        #expect(result.output.output.contains("nonisolated static var sessionCache: Caching {"))
        #expect(!result.output.output.contains("static func sessionCache("))
    }

    @Test("a scoped type injectable under two keys keeps one box")
    func multiKeyScopedKeepsOneBox() {
        let source = """
        \(Self.scopeDeclarations)

        protocol TypeA: AnyObject {}
        protocol TypeB: AnyObject {}

        @Scoped(.session)
        @Injectable<TypeA, TypeB>
        final class Dep: TypeA, TypeB {}
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)

        // One box…
        let boxCount = result.output.output.components(
            separatedBy: "static let dep = ZerkScopedBox<Dep>(scope: .session)"
        ).count - 1
        #expect(boxCount == 1)

        // …read by both keys. Storing it on `Zerk<Key>` instead would give the
        // two keys two instances, since they are distinct specializations.
        let readCount = result.output.output.components(
            separatedBy: "return _$zerk_scoped.dep.value { Dep() }"
        ).count - 1
        #expect(readCount == 2)
    }

    @Test("the scope is echoed exactly as written")
    func echoesTheScopeVerbatim() {
        let source = """
        \(Self.scopeDeclarations)

        @Scoped(.checkout)
        @Injectable
        final class Basket {}
        """

        let output = CompileFixture.generate(source: source)
        #expect(output.contains("ZerkScopedBox<Basket>(scope: .checkout)"))
    }

    @Test("a scoped type still gets an interjection point")
    func keepsItsInterjectionPoint() {
        let source = """
        \(Self.scopeDeclarations)

        protocol Caching: AnyObject {}

        @Scoped(.session)
        @Injectable<Caching>
        final class SessionCache: Caching {}
        """

        let output = CompileFixture.generate(source: source)
        #expect(output.contains("extension Zerk<Caching>.Interjection {"))
        #expect(output.contains("nonisolated var `sessionCache`: Void {}"))
        // Consulted before the box, so an interjected double never builds the
        // real instance and never poisons the cache with one.
        let guardIndex = output.range(of: "_$interjected(for: \\.`sessionCache`)")?.lowerBound
        let boxIndex = output.range(of: "_$zerk_scoped.sessionCache.value")?.lowerBound
        #expect(guardIndex != nil && boxIndex != nil)
        if let guardIndex, let boxIndex {
            #expect(guardIndex < boxIndex)
        }
    }

    // MARK: - Compilation

    @Test("a nonisolated scoped type type-checks", arguments: [nil, "MainActor"])
    func nonisolatedScopedCompiles(defaultIsolation: String?) throws {
        let source = """
        \(Self.scopeDeclarations)

        protocol Caching: AnyObject {}

        @Scoped(.session)
        nonisolated
        @Injectable<Caching>
        final class SessionCache: Caching {}
        """

        let result = try CompileFixture.run(
            source: source,
            options: .swift6(defaultIsolation: defaultIsolation)
        )
        try #require(!result.skipped)
        #expect(result.didCompile, "\(result.compilerOutput)\n\(result.generated)")
    }

    @Test("a global-actor-isolated scoped type type-checks")
    func isolatedScopedCompiles() throws {
        // The interesting half: `value` is nonisolated and takes a
        // non-`Sendable`, non-escaping closure, so the closure runs
        // synchronously in the caller's domain. If that were not so, a
        // `@MainActor` type could not be built from inside the box at all.
        let source = """
        \(Self.scopeDeclarations)

        protocol Caching: AnyObject {}

        @MainActor
        @Scoped(.session)
        @Injectable<Caching>
        final class SessionCache: Caching {
            let state = 0
        }
        """

        let result = try CompileFixture.run(source: source)
        try #require(!result.skipped)
        #expect(result.didCompile, "\(result.compilerOutput)\n\(result.generated)")
        #expect(result.generated.contains(
            "@MainActor static let sessionCache = ZerkScopedBox<SessionCache>(scope: .session)"))
    }

    @Test("a scoped type with resolved dependencies type-checks")
    func scopedWithDependenciesCompiles() throws {
        let source = """
        \(Self.scopeDeclarations)

        protocol Caching: AnyObject {}

        @Scoped(.session)
        @Injectable<Caching>
        final class SessionCache: Caching {}

        @Scoped(.session)
        @Injectable
        final class Repository {
            @InjectableProviding
            init(cache: Caching) {}
        }
        """

        let result = try CompileFixture.run(source: source)
        try #require(!result.skipped)
        #expect(result.didCompile, "\(result.compilerOutput)\n\(result.generated)")
        #expect(result.generated.contains(
            "return _$zerk_scoped.repository.value { Repository(cache: Zerk<Caching>.inject()) }"))
    }

    // MARK: - Staleness

    @Test("a singleton depending on a scoped instance is an error")
    func singletonHoldingScopedIsRefused() {
        let source = """
        \(Self.scopeDeclarations)

        protocol Caching: AnyObject {}

        @Scoped(.session)
        @Injectable<Caching>
        final class SessionCache: Caching {}

        @Singleton
        @Injectable
        final class Reporter {
            @InjectableProviding
            init(cache: Caching) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)
        let errors = result.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1)
        #expect(errors.first?.message.contains("@Singleton 'Reporter'") == true)
        #expect(errors.first?.message.contains("@Scoped(.session) 'SessionCache'") == true)
    }

    @Test("the staleness check reaches through a transient hop")
    func singletonHoldingScopedTransitively() {
        let source = """
        \(Self.scopeDeclarations)

        protocol Caching: AnyObject {}

        @Scoped(.session)
        @Injectable<Caching>
        final class SessionCache: Caching {}

        @Injectable
        struct Middle {
            @InjectableProviding
            init(cache: Caching) {}
        }

        @Singleton
        @Injectable
        final class Reporter {
            @InjectableProviding
            init(middle: Middle) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)
        let errors = result.diagnostics.filter { $0.severity == .error }
        // The transient in between is rebuilt per resolution, but the singleton
        // captured one of them — and with it, the scoped instance inside.
        #expect(errors.count == 1)
        #expect(errors.first?.message.contains("@Singleton 'Reporter'") == true)
    }

    @Test("a scope depending on a different scope is a warning, not an error")
    func crossScopeIsAWarning() {
        let source = """
        \(Self.scopeDeclarations)

        protocol Caching: AnyObject {}

        @Scoped(.session)
        @Injectable<Caching>
        final class SessionCache: Caching {}

        @Scoped(.checkout)
        @Injectable
        final class Basket {
            @InjectableProviding
            init(cache: Caching) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)
        #expect(result.diagnostics.filter { $0.severity == .error }.isEmpty)

        let warnings = result.diagnostics.filter { $0.severity == .warning }
        #expect(warnings.count == 1)
        #expect(warnings.first?.message.contains("@Scoped(.checkout) 'Basket'") == true)
        #expect(warnings.first?.message.contains("@Scoped(.session) 'SessionCache'") == true)

        // A warning still writes the file.
        #expect(result.output.output.contains("_$zerk_scoped.basket"))
    }

    @Test("two types in the same scope say nothing")
    func sameScopeIsSilent() {
        let source = """
        \(Self.scopeDeclarations)

        protocol Caching: AnyObject {}

        @Scoped(.session)
        @Injectable<Caching>
        final class SessionCache: Caching {}

        @Scoped(.session)
        @Injectable
        final class Repository {
            @InjectableProviding
            init(cache: Caching) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)
        #expect(result.diagnostics.isEmpty)
    }

    @Test("a transient depending on a scoped instance says nothing")
    func transientHoldingScopedIsFine() {
        let source = """
        \(Self.scopeDeclarations)

        protocol Caching: AnyObject {}

        @Scoped(.session)
        @Injectable<Caching>
        final class SessionCache: Caching {}

        @Injectable
        struct Consumer {
            @InjectableProviding
            init(cache: Caching) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)
        #expect(result.diagnostics.isEmpty)
    }

    @Test("a scoped instance crossing an isolation boundary gets a Sendable check")
    func crossDomainScopedIsChecked() {
        let source = """
        \(Self.scopeDeclarations)

        protocol Caching: AnyObject {}

        @MainActor
        @Scoped(.session)
        @Injectable<Caching>
        final class SessionCache: Caching {}

        @Injectable
        struct Consumer {
            @InjectableProviding
            init(cache: Caching) {}
        }
        """

        let output = CompileFixture.generate(source: source)
        #expect(output.contains("_$zerk_sendable_conformance_check(SessionCache.self)"))
        #expect(output.contains("'@Scoped SessionCache' is injected into"))
    }

    // MARK: - Refusals

    @Test("@Scoped and @Singleton together are refused")
    func scopedWithSingletonIsRefused() {
        let source = """
        \(Self.scopeDeclarations)

        @Scoped(.session)
        @Singleton
        @Injectable
        final class Both {}
        """

        let result = CompileFixture.generateWithResolution(source: source)
        let errors = result.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1)
        #expect(errors.first?.message.contains("both say how long one instance is kept") == true)
    }

    @Test("@Scoped on a value type is refused")
    func scopedOnValueTypeIsRefused() {
        let source = """
        \(Self.scopeDeclarations)

        @Scoped(.session)
        @Injectable
        struct Value {}
        """

        let result = CompileFixture.generateWithResolution(source: source)
        let errors = result.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1)
        #expect(errors.first?.message.contains("reference types") == true)
    }

    @Test("@Scoped on a generic type is refused")
    func scopedOnGenericTypeIsRefused() {
        let source = """
        \(Self.scopeDeclarations)

        @Scoped(.session)
        @Injectable
        final class Cache<E> {}
        """

        let result = CompileFixture.generateWithResolution(source: source)
        let errors = result.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1)
        #expect(errors.first?.message.contains("@Scoped cannot be applied to the generic type") == true)
    }

    @Test("a scope written any way but leading-dot is refused", arguments: [
        "MyScopes.session",
        "scopeVariable",
        "InjectionScope(\"session\")"
    ])
    func nonMemberAccessScopeIsRefused(argument: String) {
        let source = """
        @Scoped(\(argument))
        @Injectable
        final class Thing {}
        """

        let result = CompileFixture.generateWithResolution(source: source)
        let errors = result.diagnostics.filter { $0.severity == .error }
        #expect(errors.contains { $0.message.contains("leading-dot form") })
    }

    @Test("a scoped provider taking caller arguments is refused")
    func scopedWithExternalArgumentsIsRefused() {
        let source = """
        \(Self.scopeDeclarations)

        @Scoped(.session)
        @Injectable
        final class Thing {
            @InjectableProviding
            init(name: String) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)
        let errors = result.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1)
        #expect(errors.first?.message.contains("@Scoped injectables cannot accept external arguments") == true)
    }

    @Test("an async or throwing scoped provider is refused")
    func scopedWithEffectsIsRefused() {
        let source = """
        \(Self.scopeDeclarations)

        @Scoped(.session)
        @Injectable
        final class Thing {
            @InjectableProviding
            static func make() async -> Thing { Thing() }
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)
        let errors = result.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1)
        #expect(errors.first?.message.contains("@Scoped providers cannot be async or throwing") == true)
        // The reason is the box's lock, not a `static let` initializer — the
        // singleton's wording would be wrong here.
        #expect(errors.first?.message.contains("cannot be held across an 'await'") == true)
    }

    @Test("two providers for one scoped key are refused")
    func scopedWithTwoProvidersIsRefused() {
        let source = """
        \(Self.scopeDeclarations)

        @Scoped(.session)
        @Injectable
        final class Thing {
            @InjectableProviding
            static func one() -> Thing { Thing() }

            @InjectableProviding
            static func two() -> Thing { Thing() }
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)
        let errors = result.diagnostics.filter { $0.severity == .error }
        #expect(errors.contains { $0.message.contains("@Scoped 'Thing' declares multiple providers") })
    }

    // MARK: - Foreign types

    @Test("@Scoped works on a foreign-type registration")
    func scopedForeignTypeIsKept() throws {
        let source = """
        \(Self.scopeDeclarations)

        final class Client {
            init() {}
        }

        enum Registry {
            @Scoped(.session)
            @Injectable
            static var client: Client { Client() }
        }
        """

        let result = try CompileFixture.run(source: source)
        try #require(!result.skipped)
        #expect(result.didCompile, "\(result.compilerOutput)\n\(result.generated)")
        #expect(result.generated.contains("ZerkScopedBox<Client>(scope: .session)"))
        // A property-shaped provider is read, not called.
        #expect(result.generated.contains(".value { Registry.client }"))
    }
}
