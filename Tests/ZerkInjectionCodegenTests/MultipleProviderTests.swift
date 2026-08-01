//
//  MultipleProviderTests.swift
//  Zerk
//

import Testing
@testable import CodegenToolkit

/// End-to-end coverage of "a key may have more than one provider".
///
/// These go through the real pipeline — parse, resolve, generate — and, where
/// the result is a shape Swift has to accept, through `swiftc` as well. Two
/// providers on one type generate two members that share a name, and only a
/// compiler can confirm that the overloads, their defaulted arguments, and the
/// interjection protocol they all mirror actually hold together.
@Suite("Multiple providers per key")
struct MultipleProviderTests {

    // MARK: - Union of typed and untyped providers

    @Test("an untyped provider and a typed one both become members")
    func untypedAndTypedProvidersCoexist() {
        let source = """
        protocol Loading {}

        @Injectable<Loading>
        final class Loader: Loading {
            @InjectableProviding
            init() {}

            @InjectableProviding<Loading>(primary: true)
            static func cached() -> Loading { Loader() }
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("static var loader: Loading"))
        #expect(result.output.output.contains("static var cached: Loading"))
        #expect(result.output.output.contains("static func inject() -> Loading"))
        // `cached` is primary, so it is what inject() returns.
        #expect(result.output.output.contains("        cached"))
    }

    @Test("two providers for one key with no primary is an error")
    func twoProvidersWithoutPrimaryIsAnError() {
        let source = """
        protocol Loading {}

        @Injectable<Loading>
        final class Loader: Loading {
            @InjectableProviding<Loading>
            static func live() -> Loading { Loader() }

            @InjectableProviding<Loading>
            static func cached() -> Loading { Loader() }

            init() {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.contains {
            $0.severity == .error
                && $0.message.contains("'Loader' declares multiple providers for 'Loading' and none is primary")
        })
    }

    @Test("a bare initializer does not join a declared provider")
    func implicitInitializerStaysSuppressed() {
        let source = """
        protocol Loading {}

        @Injectable<Loading>
        final class Loader: Loading {
            @InjectableProviding<Loading>
            static func live() -> Loading { Loader() }

            init() {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("static var live: Loading"))
        // Declaring a provider is deliberate; the unmarked init must not
        // silently become a second one and force a primary.
        #expect(result.output.output.contains("static var loader: Loading") == false)
        #expect(result.output.output.contains("static func inject() -> Loading"))
    }

    // MARK: - Primacy is per key

    @Test("one factory can be primary for one key and not another")
    func primacyIsPerKey() {
        let source = """
        protocol Loading {}
        protocol Caching {}

        @Injectable<Loading>
        @Injectable<Caching>
        final class Store: Loading, Caching {
            @InjectableProviding<Loading>(primary: true)
            @InjectableProviding<Caching>
            static func live() -> Store { Store() }

            @InjectableProviding<Loading>
            @InjectableProviding<Caching>(primary: true)
            static func fallback() -> Store { Store() }

            init() {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        // Both factories serve both keys, but each wins only the key its own
        // attribute claimed.
        #expect(result.output.output.contains("static var live: Loading"))
        #expect(result.output.output.contains("static var fallback: Loading"))
        #expect(result.output.output.contains("static var live: Caching"))
        #expect(result.output.output.contains("static var fallback: Caching"))

        let loading = result.output.output.components(separatedBy: "extension Zerk<Loading> {")[1]
        let caching = result.output.output.components(separatedBy: "extension Zerk<Caching> {")[1]
        #expect(loading.contains("        live\n"))
        #expect(caching.contains("        fallback\n"))
    }

    @Test("an untyped primary provider claims every key on its type")
    func untypedPrimaryClaimsEveryKey() {
        let source = """
        protocol Loading {}
        protocol Caching {}

        @Injectable<Loading>
        @Injectable<Caching>
        final class Store: Loading, Caching {
            @InjectableProviding(primary: true)
            init() {}

            @InjectableProviding<Loading>
            static func live() -> Store { Store() }

            @InjectableProviding<Caching>
            static func cached() -> Store { Store() }
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)

        let loading = result.output.output.components(separatedBy: "extension Zerk<Loading> {")[1]
        let caching = result.output.output.components(separatedBy: "extension Zerk<Caching> {")[1]
        #expect(loading.contains("        store\n"))
        #expect(caching.contains("        store\n"))
    }

    // MARK: - Diagnostics that only make sense module-wide

    @Test("competing types need one @Injectable(primary:)")
    func competingTypesNeedAPrimary() {
        let source = """
        protocol Loading {}

        @Injectable<Loading>
        final class LiveLoader: Loading { init() {} }

        @Injectable<Loading>
        final class MockLoader: Loading { init() {} }
        """

        let ambiguous = CompileFixture.generateWithResolution(source: source)

        #expect(ambiguous.diagnostics.contains {
            $0.severity == .error
                && $0.message.contains("Multiple types are injectable under 'Loading'")
        })

        let resolved = CompileFixture.generateWithResolution(source: source.replacingOccurrences(
            of: "@Injectable<Loading>\nfinal class LiveLoader",
            with: "@Injectable<Loading>(primary: true)\nfinal class LiveLoader"
        ))

        #expect(resolved.diagnostics.isEmpty)
        #expect(resolved.output.output.contains("static func inject() -> Loading"))
        #expect(resolved.output.output.contains("static var liveLoader: Loading"))
        #expect(resolved.output.output.contains("static var mockLoader: Loading"))
    }

    @Test("a non-literal primary is rejected rather than read as false")
    func nonLiteralPrimaryIsRejected() {
        let source = """
        protocol Loading {}
        let isLive = true

        @Injectable<Loading>
        final class Loader: Loading {
            @InjectableProviding<Loading>(primary: isLive)
            static func live() -> Loading { Loader() }

            init() {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.contains {
            $0.severity == .error && $0.message.contains("requires a 'true' or 'false' literal")
        })
    }

    @Test("'primary' is rejected on a value")
    func primaryIsRejectedOnAValue() {
        let source = """
        enum Config {
            @Injectable(primary: true)
            static let retries: Int = 3
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.contains {
            $0.severity == .error && $0.message.contains("'primary' applies to types only")
        })
    }

    @Test("an injection method is rejected on a type")
    func injectionMethodIsRejectedOnAType() {
        let source = """
        @Injectable(.referenced)
        final class Loader { init() {} }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.contains {
            $0.severity == .error && $0.message.contains("The injection method applies to values only")
        })
    }

    // MARK: - Generated overloads have to compile

    @Test("two marked initializers generate overloads that compile")
    func twoInitializersGenerateCompilingOverloads() throws {
        let source = """
        protocol Loading {}
        protocol Disk {}
        protocol Memory {}

        @Injectable<Disk>
        final class DiskBox: Disk { init() {} }

        @Injectable<Memory>
        final class MemoryBox: Memory { init() {} }

        @Injectable<Loading>
        final class Loader: Loading {
            @InjectableProviding(primary: true)
            init(store: Disk) {}

            @InjectableProviding
            init(store: Memory) {}
        }
        """

        let result = try CompileFixture.run(source: source)

        // Both initializers are named after the type, so both members are
        // `loader` — distinguished only by their parameters, exactly as the
        // initializers are.
        #expect(result.generated.contains("static func loader(store: Disk"))
        #expect(result.generated.contains("static func loader(store: Memory"))
        // The interjection protocol has to carry both overloads; one requirement
        // for two members would leave a generated call with no declaration.
        #expect(result.generated.contains("interjectedLoader(store: Disk) -> Loading?"))
        #expect(result.generated.contains("interjectedLoader(store: Memory) -> Loading?"))
        // Both overloads are fully defaulted, so a bare `loader()` would match
        // both. inject() has to name the argument to pick the primary.
        #expect(result.generated.contains("loader(store: Zerk<Disk>.inject())"))

        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(result.didCompile, Comment(rawValue: result.compilerOutput))
    }

    @Test("two named factories generate members that compile")
    func twoFactoriesGenerateCompilingMembers() throws {
        let source = """
        protocol Loading {}

        @Injectable<Loading>
        final class Loader: Loading {
            @InjectableProviding<Loading>(primary: true)
            static func live() -> Loading { Loader() }

            @InjectableProviding<Loading>
            static func cached() -> Loading { Loader() }

            init() {}
        }
        """

        let result = try CompileFixture.run(source: source)

        #expect(result.generated.contains("static var live: Loading"))
        #expect(result.generated.contains("static var cached: Loading"))
        #expect(result.generated.contains("static func inject() -> Loading"))

        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(result.didCompile, Comment(rawValue: result.compilerOutput))
    }

    @Test("a genuine member collision is still reported")
    func genuineCollisionIsStillReported() {
        // Two *different* types whose names lower-camel-case to the same member,
        // both argument-free: same name, same parameters, so one really would
        // redeclare the other.
        let live = ProviderResolution(
            typeName: "Loader",
            injectableKey: "Loading",
            provider: .explicit(InjectingProvider(
                kind: .initializer,
                parameters: [],
                effects: .none,
                location: AttributeLocation(filePath: "/tmp/A.swift", line: 1, column: 1),
                isPrimary: true
            )),
            isTypePrimary: true,
            isShared: false,
            isSingleton: false
        )
        let duplicate = ProviderResolution(
            typeName: "Loader",
            injectableKey: "Loading",
            provider: .explicit(InjectingProvider(
                kind: .initializer,
                parameters: [],
                effects: .none,
                location: AttributeLocation(filePath: "/tmp/B.swift", line: 1, column: 1)
            )),
            isTypePrimary: true,
            isShared: false,
            isSingleton: false
        )

        let output = GeneratorOutputBuilder(
            types: [],
            values: [],
            resolutions: [live, duplicate],
            primaryResolutions: ProviderResolver.electPrimaries(among: [live, duplicate]).primaries
        ).build()

        #expect(output.diagnostics.contains {
            $0.severity == .error && $0.message.contains("same name, same parameters")
        })
    }
}
