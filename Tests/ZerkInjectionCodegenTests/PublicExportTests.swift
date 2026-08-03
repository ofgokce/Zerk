//
//  PublicExportTests.swift
//  Zerk
//

import Testing
import SwiftParser
@testable import CodegenToolkit

/// `@Injectable(public: true)` raises the generated members' access level so
/// another module can resolve the key.
///
/// It rides on the attribute that names the key, exactly as `primary:` does, so
/// a type injectable under several keys can export some and not others. The
/// generated member's signature mentions only the key, which is why a value's
/// own declaration may stay internal while its member goes public.
@Suite("Public export")
struct PublicExportTests {

    private func diagnostics(_ source: String) -> [CodegenDiagnostic] {
        CompileFixture.generateWithResolution(source: source).diagnostics
    }

    // MARK: - Types

    @Test("public: true on the attribute naming the key exports that key alone")
    func publicIsPerAttribute() {
        let output = CompileFixture.generate(source: """
        public protocol Storing: AnyObject {}
        public protocol Caching: AnyObject {}

        @Injectable<Storing>(public: true)
        @Injectable<Caching>
        public final class Store: Storing, Caching {
            @InjectableProviding
            public init() {}
        }
        """)

        #expect(output.contains("public static func inject() -> Storing"))
        #expect(output.contains("public static var store: Storing"))
        #expect(output.contains("nonisolated static func inject() -> Caching"))
        #expect(!output.contains("public static func inject() -> Caching"))
    }

    @Test("one attribute listing several keys exports all of them")
    func publicCoversEveryKeyOnTheAttribute() {
        let output = CompileFixture.generate(source: """
        public protocol Storing: AnyObject {}
        public protocol Caching: AnyObject {}

        @Injectable<Storing, Caching>(public: true)
        public final class Store: Storing, Caching {
            @InjectableProviding
            public init() {}
        }
        """)

        #expect(output.contains("public static func inject() -> Storing"))
        #expect(output.contains("public static func inject() -> Caching"))
    }

    @Test("an unparameterized attribute exports the type's own key")
    func publicOnBareAttributeExportsOwnName() {
        let output = CompileFixture.generate(source: """
        @Injectable(public: true)
        public final class Store {
            @InjectableProviding
            public init() {}
        }
        """)

        #expect(output.contains("public static func inject() -> Store"))
    }

    @Test("public: combines with primary: on one attribute")
    func publicCombinesWithPrimary() {
        let source = """
        public protocol Loading: AnyObject {}

        @Injectable<Loading>(primary: true, public: true)
        public final class LiveLoader: Loading {
            @InjectableProviding
            public init() {}
        }

        @Injectable<Loading>
        public final class MockLoader: Loading {
            @InjectableProviding
            public init() {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(!result.diagnostics.contains { $0.severity == .error })
        #expect(result.output.output.contains("public static func inject() -> Loading"))
        // Export is per key, so the losing type's member is public too — it is
        // reached through the same `Zerk<Loading>` a consuming module sees.
        #expect(result.output.output.contains("public static var liveLoader: Loading"))
    }

    @Test("public: false is the same as saying nothing")
    func publicFalseKeepsMembersInternal() {
        let output = CompileFixture.generate(source: """
        public protocol Storing: AnyObject {}

        @Injectable<Storing>(public: false)
        public final class Store: Storing {
            @InjectableProviding
            public init() {}
        }
        """)

        #expect(!output.contains("public static"))
    }

    // MARK: - Values

    @Test("public: true on a value publicizes its generated member")
    func publicValueIsExported() {
        let output = CompileFixture.generate(source: """
        @InjectableValue(public: true)
        public let apiKey: String = "abc"

        @InjectableValue
        public let otherKey: String = "def"
        """)

        #expect(output.contains("public static var apiKey: String"))
        #expect(output.contains("nonisolated static var otherKey: String"))
        #expect(!output.contains("public static var otherKey"))
    }

    @Test("an exported value may itself stay internal")
    func exportedValueNeedNotBePublic() throws {
        // Only the key appears in the member's signature. The declaration is
        // read from the accessor's *body*, which access control does not
        // constrain — so this is the one place export does not require public.
        let source = """
        enum Constants {
            @InjectableValue(.referenced, public: true)
            static let retries: Int = 3
        }
        """

        let result = try CompileFixture.run(source: source)

        #expect(result.generated.contains("public static var retries: Int"))
        #expect(result.generated.contains("Constants.retries"))

        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(result.didCompile, Comment(rawValue: result.compilerOutput))
    }

    @Test("an exported top-level referenced value reaches its private thunk")
    func exportedTopLevelReferencedValueCompiles() throws {
        // The thunk is `private` and the member is `public`; the call sits in
        // the accessor's body, so the pair is legal.
        let source = """
        @InjectableValue(.referenced, public: true)
        let host: String = "example.com"
        """

        let result = try CompileFixture.run(source: source)

        #expect(result.generated.contains("public static var host: String"))
        #expect(result.generated.contains("private func _$zerk_ref_host()"))

        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(result.didCompile, Comment(rawValue: result.compilerOutput))
    }

    // MARK: - The @InjectableValues sweep

    @Test("@InjectableValues(public:) exports every member it sweeps up")
    func sweepExportsItsMembers() {
        let output = CompileFixture.generate(source: """
        @InjectableValues(public: true)
        public enum Constants {
            public static let baseURL: String = "api.example.com"
            public static let retries: Int = 3
        }
        """)

        #expect(output.contains("public static var baseURL: String"))
        #expect(output.contains("public static var retries: Int"))
    }

    @Test("a member's own public: overrides the sweep, saying nothing inherits it")
    func memberOverridesTheSweep() {
        let output = CompileFixture.generate(source: """
        @InjectableValues(public: true)
        public enum Constants {
            @InjectableValue(public: false)
            public static let secret: String = "s"

            @InjectableValue
            public static let baseURL: String = "api.example.com"
        }
        """)

        #expect(output.contains("nonisolated static var secret: String"))
        #expect(!output.contains("public static var secret"))
        // A bare @Injectable states nothing about access, so the sweep answers.
        #expect(output.contains("public static var baseURL: String"))
    }

    @Test("an unexported sweep leaves its members internal")
    func plainSweepStaysInternal() {
        let output = CompileFixture.generate(source: """
        @InjectableValues
        public enum Constants {
            public static let baseURL: String = "api.example.com"
        }
        """)

        #expect(!output.contains("public static"))
    }

    @Test("the sweep's public: does not reach a nested type")
    func sweepDoesNotNest() {
        // Sweeping stops at the marked declaration's own members, and so does
        // the access level that rides along with it.
        let output = CompileFixture.generate(source: """
        @InjectableValues(public: true)
        public enum Constants {
            public enum Nested {
                @InjectableValue
                public static let inner: String = "x"
            }
        }
        """)

        #expect(!output.contains("public static var inner"))
    }

    // MARK: - Diagnostics

    @Test("public: on a non-public key publicizes nothing and warns")
    func nonPublicKeyWarns() {
        let source = """
        protocol Storing: AnyObject {}

        @Injectable<Storing>(public: true)
        final class Store: Storing {
            @InjectableProviding
            init() {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(!result.output.output.contains("public static"))
        #expect(result.diagnostics.contains {
            $0.severity == .warning && $0.message.contains("@Injectable(public: true) has no effect")
        })
    }

    @Test("an exported value on a non-public key warns")
    func nonPublicValueKeyWarns() {
        let source = """
        struct Settings {}

        @InjectableValue(public: true)
        let settings: Settings = Settings()
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(!result.output.output.contains("public static var settings"))
        #expect(result.diagnostics.contains {
            $0.severity == .warning && $0.message.contains("@Injectable(public: true) has no effect")
        })
    }

    @Test("a non-literal public: is an error on a type")
    func nonLiteralPublicOnTypeErrors() {
        let source = """
        let isRelease = true

        public protocol Storing: AnyObject {}

        @Injectable<Storing>(public: isRelease)
        public final class Store: Storing {
            @InjectableProviding
            public init() {}
        }
        """

        #expect(diagnostics(source).contains {
            $0.severity == .error && $0.message.contains("@Injectable(public:) requires a 'true' or 'false' literal")
        })
    }

    @Test("a non-literal public: is an error on a value")
    func nonLiteralPublicOnValueErrors() {
        let source = """
        let isRelease = true

        @InjectableValue(public: isRelease)
        public let apiKey: String = "abc"
        """

        #expect(diagnostics(source).contains {
            $0.severity == .error && $0.message.contains("@InjectableValue(public:) requires a 'true' or 'false' literal")
        })
    }

    @Test("a non-literal public: is an error on the sweep")
    func nonLiteralPublicOnSweepErrors() {
        let source = """
        let isRelease = true

        @InjectableValues(public: isRelease)
        public enum Constants {
            public static let baseURL: String = "api.example.com"
        }
        """

        #expect(diagnostics(source).contains {
            $0.severity == .error && $0.message.contains("@InjectableValues(public:) requires a 'true' or 'false' literal")
        })
    }
}
