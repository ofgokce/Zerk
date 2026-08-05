//
//  KeyPathInjectionTests.swift
//  Zerk
//

import Testing
@testable import CodegenToolkit

/// Coverage of `@Injected(\.member)` and the companion `static var`s that give
/// it something to point at.
///
/// A key path can name a property but never a method, so a provider that
/// generates `static func live(store:)` is out of reach until an argument-free
/// `static var live` exists beside it. The conditions on emitting that var are
/// all compiler constraints rather than taste, and each is pinned here.
@Suite("Key-path injection")
struct KeyPathInjectionTests {

    private static let graph = """
    protocol Storing {}

    @Injectable<Storing>
    final class Disk: Storing {
        @InjectableProviding
        init() {}
    }
    """

    @Test("the generated file declares the key-path overload")
    func keyPathOverloadIsDeclared() {
        let result = CompileFixture.generateWithResolution(source: Self.graph)

        // The `T` here is the *macro's* own generic parameter, not Zerk's —
        // whose parameter is named `Injectable`. A rename sweep skips this line.
        #expect(result.output.output.contains(
            "macro Injected<T>(_ keyPath: KeyPath<Zerk<T>.Type, T>) = #externalMacro(module: \"ZerkMacros\", type: \"InjectedMacro\")"
        ))
    }

    @Test("a fully resolvable factory gains an argument-free var")
    func resolvableFactoryGainsAVar() throws {
        let source = """
        \(Self.graph)

        protocol Loading {}

        @Injectable<Loading>
        final class Loader: Loading {
            @InjectableProviding<Loading>
            static func live(store: Storing) -> Loading { Loader() }

            init() {}
        }
        """

        let result = try CompileFixture.run(source: source)

        // The method stays; the var is additional.
        #expect(result.generated.contains("static func live(store: Storing = Zerk<Storing>.inject()) -> Loading"))
        #expect(result.generated.contains("static var live: Loading {"))
        #expect(result.generated.contains("        live()"))

        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(result.didCompile, Comment(rawValue: result.compilerOutput))
    }

    @Test("a member with a caller-supplied parameter gains no var")
    func unresolvableParameterGainsNoVar() {
        // Nothing could supply `label`, so an argument-free var has no body.
        let source = """
        protocol Loading {}

        @Injectable<Loading>
        final class Loader: Loading {
            @InjectableProviding<Loading>
            static func live(label: String) -> Loading { Loader() }

            init() {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.output.output.contains("static func live(label: String) -> Loading"))
        #expect(!result.output.output.contains("static var live: Loading"))
    }

    @Test("an effectful member gains no var", arguments: ["async", "throws"])
    func effectfulMemberGainsNoVar(_ effect: String) {
        // Swift refuses to form a key path to an async or throws property, and
        // for an argument-free one the two names would collide outright.
        let source = """
        \(Self.graph)

        protocol Loading {}

        @Injectable<Loading>
        final class Loader: Loading {
            @InjectableProviding<Loading>
            static func live(store: Storing) \(effect) -> Loading { Loader() }

            init() {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(!result.output.output.contains("static var live: Loading"))
    }

    @Test("an argument-free member is already a var and gains nothing")
    func argumentFreeMemberIsUnchanged() {
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

        // One `live`, shaped as a property, exactly as before.
        let count = result.output.output.components(separatedBy: "static var live: Loading").count - 1
        #expect(count == 1)
        #expect(!result.output.output.contains("static func live("))
    }

    @Test("two providers sharing a member name gain no var")
    func sharedMemberNameGainsNoVar() throws {
        // `loader(store:)` twice is legal — the overloads differ by parameter
        // type — but `loader` once is a redeclaration, and `loader()` would be
        // ambiguous between them.
        let source = """
        protocol Storing {}
        protocol Other {}

        @Injectable<Storing>
        final class Disk: Storing {
            @InjectableProviding
            init() {}
        }

        @Injectable<Other>
        final class Mem: Other {
            @InjectableProviding
            init() {}
        }

        protocol Loading {}

        @Injectable<Loading>
        final class Loader: Loading {
            @InjectableProviding<Loading>(primary: true)
            init(store: Storing) {}

            @InjectableProviding<Loading>
            init(store: Other) {}
        }
        """

        let result = try CompileFixture.run(source: source)

        #expect(!result.generated.contains("static var loader: Loading"))

        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(result.didCompile, Comment(rawValue: result.compilerOutput))
    }

    @Test("@Injectable(public:) publicizes the members a key path would name, and type-checks")
    func sharedPublicizesKeyPathTargets() throws {
        // Without this a consuming module can call inject() but cannot name a
        // member, so `@Injected(\.staging)` has nothing to point at across a
        // module boundary.
        let source = """
        public protocol ApiServicing: AnyObject {}

        @Injectable<ApiServicing>(public: true)
        public final class ApiService: ApiServicing {
            @InjectableProviding<ApiServicing>(primary: true)
            public static func live() -> ApiServicing { ApiService() }

            @InjectableProviding<ApiServicing>
            public static func staging() -> ApiServicing { ApiService() }

            public init() {}
        }
        """

        let result = try CompileFixture.run(source: source)

        #expect(result.generated.contains("public static var live: ApiServicing"))
        #expect(result.generated.contains("public static var staging: ApiServicing"))
        #expect(result.generated.contains("public static func inject() -> ApiServicing"))

        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(result.didCompile, Comment(rawValue: result.compilerOutput))
    }

    @Test("a shared singleton exposes its getter but not its storage")
    func sharedSingletonKeepsStoragePrivate() throws {
        let source = """
        public protocol Storing: AnyObject {}

        @Singleton
        @Injectable<Storing>(public: true)
        public final class Store: Storing {
            @InjectableProviding
            public init() {}
        }
        """

        let result = try CompileFixture.run(source: source)

        #expect(result.generated.contains("public static var store: Storing"))
        // The shared instance lives in the private namespace either way.
        #expect(result.generated.contains("private enum _$zerk_singletons {"))
        #expect(!result.generated.contains("public static let store"))

        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(result.didCompile, Comment(rawValue: result.compilerOutput))
    }

    @Test("a key-path use is not checked against the primary's chain")
    func keyPathUseSkipsTheChainCheck() {
        // The primary is async, so a plain @Injected would be rejected. A key
        // path names a different member, so that check does not apply — and
        // anything a key path can reach is effect-free by construction.
        let source = """
        \(Self.graph)

        protocol Loading {}

        @Injectable<Loading>
        final class Loader: Loading {
            @InjectableProviding<Loading>(primary: true)
            static func slow(store: Storing) async -> Loading { Loader() }

            @InjectableProviding<Loading>
            static func fast(store: Storing) -> Loading { Loader() }

            init() {}
        }

        struct Consumer {
            @Injected(\\.fast)
            var loader: Loading
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(!result.diagnostics.contains { $0.message.contains("cannot resolve it") })
    }

    @Test("a stated key is what the chain check validates, not the declared type")
    func statedKeyDrivesTheChainCheck() {
        // `Serving`'s primary is async, so a bare @Injected would be rejected.
        // `@Injected<Fast>` asks for a different key, whose chain is fine.
        let source = """
        \(Self.graph)

        protocol Serving {}

        @Injectable<Serving>
        final class Slow: Serving {
            @InjectableProviding<Serving>
            static func make(store: Storing) async -> Serving { Slow() }

            init() {}
        }

        @Injectable
        final class Fast: Serving {
            @InjectableProviding
            init() {}
        }

        struct Consumer {
            @Injected<Fast>
            var service: Serving
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(!result.diagnostics.contains { $0.message.contains("cannot resolve it") })
    }

    @Test("a stated key with an async chain is still rejected")
    func statedKeyWithAsyncChainIsRejected() {
        let source = """
        \(Self.graph)

        protocol Serving {}

        @Injectable<Serving>
        final class Slow: Serving {
            @InjectableProviding<Serving>
            static func make(store: Storing) async -> Serving { Slow() }

            init() {}
        }

        struct Consumer {
            @Injected<Serving>
            var service: Serving
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.contains {
            $0.severity == .error && $0.message.contains("cannot resolve it")
        })
    }

    @Test("a plain @Injected on an async chain is still rejected")
    func plainInjectedStillChecksTheChain() {
        let source = """
        \(Self.graph)

        protocol Loading {}

        @Injectable<Loading>
        final class Loader: Loading {
            @InjectableProviding<Loading>
            static func slow(store: Storing) async -> Loading { Loader() }

            init() {}
        }

        struct Consumer {
            @Injected
            var loader: Loading
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.contains {
            $0.severity == .error && $0.message.contains("cannot resolve it")
        })
    }
}
