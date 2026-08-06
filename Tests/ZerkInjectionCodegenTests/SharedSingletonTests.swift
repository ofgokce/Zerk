//
//  SharedSingletonTests.swift
//  Zerk
//

import Testing
@testable import CodegenToolkit

/// Coverage of "a `@Singleton` is one instance, however many keys it claims".
///
/// The shape under test is `_$zerk_singletons`: shared storage held once per
/// type, read through a per-key getter. Storing it on `Zerk<Key>` instead —
/// which is what Zerk used to do — gives a type injectable under two keys two
/// instances, because `Zerk<A>` and `Zerk<B>` are distinct specializations with
/// distinct static storage. That failure is invisible in a golden string, so the
/// cases here go through the real pipeline and, where it matters, through
/// `swiftc`.
@Suite("Shared singletons")
struct SharedSingletonTests {

    // MARK: - One instance across every key

    @Test("a singleton injectable under two keys stores one instance")
    func multiKeySingletonStoresOneInstance() {
        let source = """
        protocol TypeA: AnyObject {}
        protocol TypeB: AnyObject {}

        @Singleton
        @Injectable<TypeA, TypeB>
        final class Dep: TypeA, TypeB {}
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.diagnostics.isEmpty)

        // Exactly one storage declaration, typed as the concrete type so both
        // keys can be served from it.
        let storageCount = result.output.output.components(
            separatedBy: "static let dep: Dep = Dep()"
        ).count - 1
        #expect(storageCount == 1)
        #expect(result.output.output.contains("private enum _$zerk_singletons {"))

        // Both keys read that one instance rather than building their own.
        #expect(result.output.output.contains("nonisolated static var dep: TypeA {"))
        #expect(result.output.output.contains("nonisolated static var dep: TypeB {"))
        let readCount = result.output.output.components(
            separatedBy: "return _$zerk_singletons.dep"
        ).count - 1
        #expect(readCount == 2)

        // The old shape built a fresh instance per key.
        #expect(!result.output.output.contains("static let dep: TypeA"))
        #expect(!result.output.output.contains("static let dep: TypeB"))
    }

    @Test("a multi-key singleton type-checks")
    func multiKeySingletonCompiles() throws {
        let source = """
        protocol TypeA: AnyObject {}
        protocol TypeB: AnyObject {}

        @Singleton
        @Injectable<TypeA, TypeB>
        final class Dep: TypeA, TypeB {}
        """

        let result = try CompileFixture.run(source: source)

        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(result.didCompile, Comment(rawValue: result.compilerOutput))
    }

    @Test("an isolated multi-key singleton type-checks")
    func isolatedMultiKeySingletonCompiles() throws {
        let source = """
        protocol TypeA: AnyObject {}
        protocol TypeB: AnyObject {}

        @MainActor
        @Singleton
        @Injectable<TypeA, TypeB>
        final class Dep: TypeA, TypeB {}
        """

        let result = try CompileFixture.run(source: source)

        // Global-actor isolation protects the storage, so it takes the attribute
        // rather than the `nonisolated(unsafe)` escape hatch.
        #expect(result.generated.contains("@MainActor static let dep: Dep = Dep()"))

        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(result.didCompile, Comment(rawValue: result.compilerOutput))
    }

    @Test("two singletons each get their own storage")
    func twoSingletonsGetSeparateStorage() {
        let source = """
        protocol TypeA: AnyObject {}

        @Singleton
        @Injectable<TypeA>
        final class Dep: TypeA {}

        @Singleton
        @Injectable
        final class Other {}
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("static let dep: Dep = Dep()"))
        #expect(result.output.output.contains("static let other: Other = Other()"))
    }

    // MARK: - Storage type

    @Test("a single-key singleton may still be built by a factory returning the key")
    func singleKeyFactoryReturningKeyIsAccepted() {
        // Storage is typed as the provider's declared return type, so this — the
        // shape that worked before shared storage existed — keeps working.
        let source = """
        protocol Loading: AnyObject {}

        @Singleton
        @Injectable<Loading>
        final class Loader: Loading {
            @InjectableProviding<Loading>
            static func live() -> Loading { Loader() }

            init() {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.diagnostics.isEmpty)
        #expect(result.output.output.contains("static let loader: Loading = Loader.live()"))
    }

    @Test("a multi-key singleton built by a factory returning a key is an error")
    func multiKeyFactoryReturningKeyIsAnError() {
        // Storage typed 'TypeA' cannot serve Zerk<TypeB>, and Zerk reads syntax
        // so it cannot discover that the factory happens to return a Dep.
        let source = """
        protocol TypeA: AnyObject {}
        protocol TypeB: AnyObject {}

        @Singleton
        @Injectable<TypeA, TypeB>
        final class Dep: TypeA, TypeB {
            @InjectableProviding<TypeA>
            @InjectableProviding<TypeB>
            static func live() -> TypeA { Dep() }

            init() {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.contains {
            $0.severity == .error
                && $0.message.contains("must return 'Dep' rather than 'TypeA'")
        })
    }

    @Test("a multi-key singleton built by a factory returning the concrete type is accepted")
    func multiKeyFactoryReturningConcreteTypeIsAccepted() {
        let source = """
        protocol TypeA: AnyObject {}
        protocol TypeB: AnyObject {}

        @Singleton
        @Injectable<TypeA, TypeB>
        final class Dep: TypeA, TypeB {
            @InjectableProviding<TypeA>
            @InjectableProviding<TypeB>
            static func live() -> Dep { Dep() }

            init() {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.diagnostics.isEmpty)
        #expect(result.output.output.contains("static let dep: Dep = Dep.live()"))
    }

    // MARK: - One provider across all keys

    @Test("a singleton naming a different provider per key is an error")
    func differentProviderPerKeyIsAnError() {
        let source = """
        protocol TypeA: AnyObject {}
        protocol TypeB: AnyObject {}

        @Singleton
        @Injectable<TypeA, TypeB>
        final class Dep: TypeA, TypeB {
            @InjectableProviding<TypeA>
            static func viaA() -> Dep { Dep() }

            @InjectableProviding<TypeB>
            static func viaB() -> Dep { Dep() }

            init() {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.contains {
            $0.severity == .error
                && $0.message.contains("resolves to different providers")
                && $0.message.contains("'viaA'")
                && $0.message.contains("'viaB'")
        })
        // Nothing to store, so nothing is emitted for either key.
        #expect(!result.output.output.contains("_$zerk_singletons"))
    }

    @Test("a singleton whose one factory serves both keys is accepted")
    func oneFactoryForAllKeysIsAccepted() {
        // Two attributes, one declaration: the resolver compares declarations,
        // not records, so this is a single provider rather than two.
        let source = """
        protocol TypeA: AnyObject {}
        protocol TypeB: AnyObject {}

        @Singleton
        @Injectable<TypeA, TypeB>
        final class Dep: TypeA, TypeB {
            @InjectableProviding
            init() {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.diagnostics.isEmpty)
        #expect(result.output.output.contains("static let dep: Dep = Dep()"))
    }

    // MARK: - Interjection

    @Test("interjection is consulted per read rather than baked into the storage")
    func interjectionGuardsTheGetter() {
        let source = """
        protocol TypeA: AnyObject {}
        protocol TypeB: AnyObject {}

        @Singleton
        @Injectable<TypeA, TypeB>
        final class Dep: TypeA, TypeB {}
        """

        let result = CompileFixture.generateWithResolution(source: source)

        // The guard cannot live in the storage — it is per key, and there is one
        // storage for both keys — so each getter carries its own.
        #expect(result.output.output.contains("_$interjected(for: \\.`dep`)"))
        // A point per key, since Zerk<TypeA> and Zerk<TypeB> are separate
        // specializations even though one instance backs both.
        #expect(result.output.output.contains("extension Zerk<TypeA>.Interjection {"))
        #expect(result.output.output.contains("extension Zerk<TypeB>.Interjection {"))

        // Storage is a plain initialization, with no guard folded into it.
        #expect(result.output.output.contains("static let dep: Dep = Dep()"))
        #expect(!result.output.output.contains("static let dep: Dep = {"))
    }

    // MARK: - One provider in total, not one per key

    @Test("a multi-key singleton with two providers for one key is an error")
    func multiKeySingletonWithTwoProvidersForOneKey() {
        // The per-key half of the rule, on a type where the cross-key half also
        // has something to say. Both members would read the same storage, so
        // asking for `two` would hand back whatever `one` built.
        let result = CompileFixture.generateWithResolution(source: """
        protocol A {}
        protocol B {}

        @Singleton
        @Injectable<A>
        @Injectable<B>
        final class L: A, B {
            @InjectableProviding
            static func one() -> L { .init() }

            @InjectableProviding
            static func two() -> L { .init() }

            init() {}
        }
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error
                && $0.message.contains("@Singleton 'L' declares multiple providers for")
                && $0.message.contains("exactly one provider in total")
        })
        // Nothing is emitted for a type with no legal shared instance.
        #expect(!result.output.output.contains("_$zerk_singletons"))
    }

    @Test("the two checks together mean exactly one provider", arguments: [
        // Every key served by one untyped factory.
        "@InjectableProviding\n    static func common() -> L { .init() }",
        // One factory bound to each key explicitly — still one declaration.
        "@InjectableProviding<A>\n    @InjectableProviding<B>\n    static func common() -> L { .init() }",
    ])
    func oneDeclarationServingEveryKeyIsAccepted(provider: String) throws {
        // A factory bound to two keys yields one record per attribute, and the
        // cross-key check compares *locations* precisely so that reads as one
        // provider rather than two.
        let source = """
        protocol A {}
        protocol B {}

        @Singleton
        @Injectable<A>
        @Injectable<B>
        final class L: A, B {
            \(provider)

            init() {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        // One instance, stored once, read through both keys.
        #expect(result.output.output.contains("static let l: L = L.common()"))
        #expect(result.output.output.contains("extension Zerk<A>"))
        #expect(result.output.output.contains("extension Zerk<B>"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("a key left without the marked provider is caught")
    func keyWithoutTheMarkedProviderIsCaught() {
        // `@InjectableProviding<A>` serves only A, so B falls through to the
        // initializer — which is a second way to build the one instance.
        let result = CompileFixture.generateWithResolution(source: """
        protocol A {}
        protocol B {}

        @Singleton
        @Injectable<A>
        @Injectable<B>
        final class L: A, B {
            @InjectableProviding<A>
            static func liveA() -> L { .init() }

            init() {}
        }
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error && $0.message.contains("resolves to different providers")
        })
    }
}
