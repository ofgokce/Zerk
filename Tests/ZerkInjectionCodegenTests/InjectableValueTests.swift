//
//  InjectableValueTests.swift
//  Zerk
//

import Testing
import SwiftParser
@testable import CodegenToolkit

/// `@InjectableValue` — the marker split out of `@Injectable` so that types and
/// values stop sharing one attribute.
///
/// A type is *built* by a provider and matched by its key; a value is *read* from
/// a declaration and matched by key **and name**. This covers what the split
/// bought beyond the rename: effectful values, and the parametric form, whose
/// parameters behave exactly as an `@InjectableProviding` provider's do.
@Suite("@InjectableValue")
struct InjectableValueTests {

    private func result(_ source: String) -> (output: GeneratorOutput, diagnostics: [CodegenDiagnostic]) {
        CompileFixture.generateWithResolution(source: source)
    }

    // MARK: - Effects

    @Test("an async throwing getter carries its effects onto the member")
    func effectfulValueDeclaresItsEffects() {
        let output = CompileFixture.generate(source: """
        @InjectableValue
        var token: String {
            get async throws { "tok" }
        }
        """)

        #expect(output.contains("static var token: String {"))
        #expect(output.contains("get async throws {"))
    }

    @Test("a multi-statement getter is emitted as statements, not as one expression")
    func multiStatementBodySurvives() {
        // The generated getter opens with the interjection guard, so Swift's
        // implicit single-expression return no longer applies and the body has
        // to arrive already in statement form.
        let output = CompileFixture.generate(source: """
        @InjectableValue
        var token: String {
            get async throws {
                let base = "a"
                return base + "b"
            }
        }
        """)

        #expect(output.contains("let base = \"a\""))
        #expect(output.contains("return base + \"b\""))
        #expect(!output.contains("return let base"))
    }

    @Test("resolving an effectful value moves it into the body and propagates")
    func effectfulValuePropagates() {
        let source = """
        @InjectableValue
        var token: String {
            get async throws { "tok" }
        }

        @Injectable
        final class Repo {
            @InjectableProviding
            init(token: String) {}
        }
        """

        let result = self.result(source)

        #expect(result.diagnostics.isEmpty)
        // A default argument cannot `try`/`await`, so it resolves in the body.
        #expect(result.output.output.contains("try await Zerk<String>.token"))
        #expect(result.output.output.contains("static func inject() async throws -> Repo"))
        #expect(!result.output.output.contains("token: String = Zerk<String>.token"))
    }

    @Test("a referenced effectful value reads through with its effects")
    func referencedEffectfulValue() {
        let output = CompileFixture.generate(source: """
        enum Src {
            @InjectableValue(.referenced)
            static var token: String {
                get async throws { "tok" }
            }
        }
        """)

        #expect(output.contains("return try await Src.token"))
    }

    @Test("a plain value stays a defaulted argument")
    func plainValueStaysDefaulted() {
        let source = """
        @InjectableValue
        var retries: Int { 3 }

        @Injectable
        final class Repo {
            @InjectableProviding
            init(retries: Int) {}
        }
        """

        let result = self.result(source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("retries: Int = Zerk<Int>.retries"))
        #expect(result.output.output.contains("static func inject() -> Repo"))
    }
    @Test("two values of one key and name are an error")
    func duplicateValueNamesAreAnError() {
        // Without this the two identical `static var`s land in one
        // `extension Zerk<String>` and the *generated* file fails with
        // `invalid redeclaration`, in a file the developer never wrote.
        let source = """
        enum A { @InjectableValue static var dup: String { "a" } }
        enum B { @InjectableValue static var dup: String { "b" } }
        """

        #expect(result(source).diagnostics.contains {
            $0.severity == .error && $0.message.contains("'dup' is declared as a 'String' value more than once")
        })
    }
    @Test("a value colliding with a provider's member is an error")
    func valueCollidingWithProviderIsAnError() {
        let source = """
        protocol Storing {}

        @Injectable<Storing>
        final class Store: Storing {
            @InjectableProviding
            init() {}
        }

        @InjectableValue<Storing>
        var store: Storing { Store() }
        """

        #expect(result(source).diagnostics.contains {
            $0.severity == .error
                && $0.message.contains("collides with the @InjectableValue 'store'")
                && $0.message.contains("Rename the @InjectableValue")
        })
    }

    @Test("one value under several keys is not a collision")
    func oneValueUnderSeveralKeysIsFine() {
        // A value registered under two keys yields one record per key. Grouping
        // those by name alone would call the declaration a duplicate of itself.
        let source = """
        protocol Storing {}
        protocol Caching {}

        @InjectableValue<Storing>
        @InjectableValue<Caching>
        var store: Any { 0 }
        """

        #expect(!result(source).diagnostics.contains { $0.severity == .error })
    }

    @Test("the same name under different keys is not a collision")
    func sameNameDifferentKeysIsFine() {
        let source = """
        enum A { @InjectableValue static var limit: Int { 1 } }
        enum B { @InjectableValue static var limit: String { "s" } }
        """

        #expect(!result(source).diagnostics.contains { $0.severity == .error })
    }

    // MARK: - Functions are not values

    @Test("@InjectableValue on a function is refused, and says what to write")
    func functionIsRefused() {
        // A value is *read* and matched by key and name; a function with
        // parameters is something the graph *builds*. `@Injectable` on the same
        // declaration registers exactly that.
        let source = """
        enum Formatting {
            @InjectableValue
            static func caption(label: String) -> String { label }
        }
        """

        #expect(result(source).diagnostics.contains {
            $0.severity == .error
                && $0.message.contains("@InjectableValue cannot be applied to a function")
                && $0.message.contains("'@Injectable'")
        })
        #expect(!result(source).output.output.contains("caption"))
    }

    @Test("a global function carrying the marker is refused too")
    func globalFunctionIsRefused() {
        let source = """
        @InjectableValue
        func caption(label: String) -> String { label }
        """

        #expect(result(source).diagnostics.contains {
            $0.severity == .error && $0.message.contains("cannot be applied to a function")
        })
    }

    @Test("an argument-free function is refused as well")
    func argumentFreeFunctionIsRefused() {
        // Not about the parameters: a function is the wrong *shape* for a
        // value, whether or not it happens to take any.
        let source = """
        enum Formatting {
            @InjectableValue
            static func banner() -> String { "hi" }
        }
        """

        #expect(result(source).diagnostics.contains {
            $0.severity == .error && $0.message.contains("cannot be applied to a function")
        })
    }

    @Test("the @InjectableValues sweep ignores functions in silence")
    func sweepIgnoresFunctions() {
        // The sweep is a statement about the type, not a promise about every
        // member — so a function it cannot take is skipped rather than
        // reported, exactly as an ineligible property is.
        let source = """
        @InjectableValues
        enum AppConstants {
            static let baseURL: String = "api.example.com"
            static let retries: Int = 3

            static func caption(label: String) -> String { label }
            static func banner() -> String { "hi" }
        }
        """

        let result = self.result(source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("static var baseURL: String"))
        #expect(result.output.output.contains("static var retries: Int"))
        #expect(!result.output.output.contains("caption"))
        #expect(!result.output.output.contains("banner"))
    }

    @Test("a swept type's function may still be an @Injectable provider")
    func sweptTypeFunctionCanStillRegisterAType() throws {
        // The replacement for the parametric form: the function registers the
        // type it returns, with itself as the provider.
        let source = """
        struct Caption { let text: String }

        @InjectableValues
        enum AppConstants {
            static let prefix: String = "#"

            @Injectable(typeNamed: true)
            static func makeCaption(prefix: String) -> Caption { .init(text: prefix) }
        }
        """

        let result = self.result(source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("static var prefix: String"))
        // A real key, reached through inject() like any other type.
        #expect(result.output.output.contains("extension Zerk<Caption> {"))
        #expect(result.output.output.contains(
            "static func caption(prefix: String = Zerk<String>.prefix) -> Caption {"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }
}
