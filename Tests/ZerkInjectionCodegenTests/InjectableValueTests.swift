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

    // MARK: - Parametric values

    @Test("a parametric value resolves what it can and exposes what it cannot")
    func parametricValueSplitsItsParameters() {
        let output = CompileFixture.generate(source: """
        @Injectable
        final class Config {
            @InjectableProviding
            init() {}
        }

        enum Values {
            @InjectableValue
            static func greeting(config: Config, name: String) -> String { name }
        }
        """)

        #expect(output.contains("static func greeting(config: Config = Zerk<Config>.inject(), name: String) -> String"))
        // The member calls the developer's own function rather than copying it.
        #expect(output.contains("return Values.greeting(config: config, name: name)"))
    }

    @Test("a parametric value's unresolved parameter bubbles to the consumer")
    func parametricParameterBubbles() {
        let source = """
        @Injectable
        final class Config {
            @InjectableProviding
            init() {}
        }

        enum Values {
            @InjectableValue
            static func greeting(config: Config, name: String) -> String { name }
        }

        @Injectable
        final class Screen {
            @InjectableProviding
            init(greeting: String) {}
        }
        """

        let result = self.result(source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("static func inject(name: String) -> Screen"))
        #expect(result.output.output.contains("Zerk<String>.greeting(name: name)"))
    }

    @Test("a fully resolvable parametric value is reachable as a defaulted argument")
    func fullyResolvableParametricValueDefaults() {
        let source = """
        @Injectable
        final class Config {
            @InjectableProviding
            init() {}
        }

        enum Values {
            @InjectableValue
            static func banner(config: Config) -> String { "b" }
        }

        @Injectable
        final class Screen {
            @InjectableProviding
            init(banner: String) {}
        }
        """

        let result = self.result(source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("banner: String = Zerk<String>.banner()"))
        #expect(result.output.output.contains("static func inject() -> Screen"))
    }

    @Test("a parametric value is matched by name, so it never answers for its key alone")
    func parametricValueIsMatchedByName() {
        let source = """
        @Injectable
        final class Config {
            @InjectableProviding
            init() {}
        }

        enum Values {
            @InjectableValue
            static func banner(config: Config) -> String { "b" }
        }

        @Injectable
        final class Screen {
            @InjectableProviding
            init(somethingElse: String) {}
        }
        """

        let result = self.result(source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("static func inject(somethingElse: String) -> Screen"))
        #expect(!result.output.output.contains("somethingElse: String = "))
    }

    @Test("a parametric value never wins its key's inject()")
    func parametricValueIsNeverPrimary() {
        // Values are reached by name. Emitting `inject()` for `String` from one
        // would make every unnamed `String` resolve to it.
        let output = CompileFixture.generate(source: """
        @Injectable
        final class Config {
            @InjectableProviding
            init() {}
        }

        enum Values {
            @InjectableValue
            static func banner(config: Config) -> String { "b" }
        }
        """)

        #expect(output.contains("static func banner(config: Config"))
        #expect(!output.contains("static func inject() -> String"))
    }

    @Test("parameter markers apply to a parametric value")
    func parametricValueHonoursMarkers() {
        let source = """
        @Injectable
        final class Config {
            @InjectableProviding
            init() {}
        }

        @InjectableValue
        var salt: String { "s" }

        enum Values {
            @InjectableValue
            static func token(config: Config, @noninjected salt: String) -> String { salt }
        }
        """

        let result = self.result(source)

        #expect(result.diagnostics.isEmpty)
        // `salt` would otherwise match the value of the same name and type.
        #expect(result.output.output.contains("static func token(config: Config = Zerk<Config>.inject(), salt: String) -> String"))
    }

    @Test("a top-level parametric value goes through a thunk")
    func topLevelParametricValueUsesAThunk() {
        // Inside `extension Zerk<String>` an unqualified `greeting(…)` resolves
        // to the generated member of that name, so calling it directly would
        // recurse — the same reason a top-level `.referenced` value has one.
        let output = CompileFixture.generate(source: """
        @Injectable
        final class Config {
            @InjectableProviding
            init() {}
        }

        @InjectableValue
        func greeting(config: Config, name: String) -> String { name }
        """)

        #expect(output.contains("private func _$zerk_call_greeting(config: Config, name: String) -> String"))
        #expect(output.contains("return _$zerk_call_greeting(config: config, name: name)"))
    }

    @Test("a nested parametric value is qualified rather than thunked")
    func nestedParametricValueIsQualified() {
        let output = CompileFixture.generate(source: """
        enum Values {
            @InjectableValue
            static func greeting(name: String) -> String { name }
        }
        """)

        #expect(output.contains("return Values.greeting(name: name)"))
        #expect(!output.contains("_$zerk_call_greeting"))
    }

    @Test("an effectful parametric value propagates through the consumer")
    func effectfulParametricValuePropagates() {
        let source = """
        enum Values {
            @InjectableValue
            static func token(name: String) async throws -> String { name }
        }

        @Injectable
        final class Repo {
            @InjectableProviding
            init(token: String) {}
        }
        """

        let result = self.result(source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("static func token(name: String) async throws -> String"))
        #expect(result.output.output.contains("static func inject(name: String) async throws -> Repo"))
    }

    @Test("a parametric value gets an interjection point")
    func parametricValueInterjectionIsFunctionShaped() {
        let output = CompileFixture.generate(source: """
        enum Values {
            @InjectableValue
            static func greeting(name: String) -> String { name }
        }
        """)

        // Unique name for its key, so the point takes the bare form.
        #expect(output.contains("var `greeting`: Void {}"))
    }

    // MARK: - Name collisions

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

    @Test("a property and a parametric value of one name are an error")
    func propertyAndParametricValueCollide() {
        // These two *compile* — a var and a func are different declarations —
        // but neither can be matched, since matching demands a unique one. The
        // parameter silently became caller-supplied before this was reported.
        let source = """
        @InjectableValue
        var clash: String { "p" }

        enum C {
            @InjectableValue
            static func clash(x: Int) -> String { "f" }
        }
        """

        #expect(result(source).diagnostics.contains {
            $0.severity == .error && $0.message.contains("'clash' is declared as a 'String' value more than once")
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

    // MARK: - Markers on a parametric value

    @Test("@autoinjected on a parametric value is honoured, not reported inert")
    func autoinjectedOnParametricValueIsNotInert() {
        // The enclosing type is a namespace, not the thing being built, so the
        // "is it @Injectable?" question the inert check asks does not apply.
        let source = """
        @Injectable
        final class Config {
            @InjectableProviding
            init() {}
        }

        enum V {
            @InjectableValue
            static func caption(@autoinjected config: Config, label: String) -> String { label }
        }
        """

        let result = self.result(source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("static func caption(config: Config = Zerk<Config>.inject(), label: String) -> String"))
    }

    // MARK: - The @InjectableValues sweep

    @Test("the sweep picks up eligible functions as parametric values")
    func sweepCollectsFunctions() {
        let output = CompileFixture.generate(source: """
        @Injectable
        final class Logger {
            @InjectableProviding
            init() {}
        }

        @InjectableValues(public: true)
        public enum Constants {
            public static let baseURL: String = "u"
            public static func caption(logger: Logger, label: String) -> String { label }
        }
        """)

        #expect(output.contains("public static var baseURL: String"))
        #expect(output.contains("public static func caption(logger: Logger = Zerk<Logger>.inject(), label: String) -> String"))
    }

    @Test("the sweep skips functions it cannot inject")
    func sweepSkipsIneligibleFunctions() {
        // Marking a type is a statement about the type, not a promise that every
        // member qualifies — so these are skipped rather than reported.
        let output = CompileFixture.generate(source: """
        @InjectableValues
        enum Constants {
            @NonInjectable
            static func optedOut() -> String { "h" }

            static func generic<T>(x: T) -> Int { 1 }
            static func noReturn() {}
            private static func hidden() -> Double { 1 }
            func instanceMethod() -> String { "i" }
        }
        """)

        #expect(!output.contains("optedOut"))
        #expect(!output.contains("generic"))
        #expect(!output.contains("noReturn"))
        #expect(!output.contains("hidden"))
        #expect(!output.contains("instanceMethod"))
    }

    @Test("a function outside a swept type needs its own marker")
    func unsweptFunctionIsNotCollected() {
        let output = CompileFixture.generate(source: """
        enum Constants {
            static func caption(label: String) -> String { label }
        }
        """)

        #expect(!output.contains("caption"))
    }

    // MARK: - Aliases

    @Test("a parametric value's parameter keys fold onto their representatives")
    func parametricParametersFollowAliases() {
        let source = """
        protocol Storing {}

        @ZerkAlias
        typealias Persisting = Storing

        @Injectable<Storing>
        final class FileStore: Storing {
            @InjectableProviding
            init() {}
        }

        enum Values {
            @InjectableValue
            static func label(store: Persisting) -> String { "x" }
        }
        """

        let result = self.result(source)

        #expect(result.diagnostics.isEmpty)
        // Folded to `Storing`, so the parameter resolves instead of bubbling.
        // The spelling stays as written — `Zerk<Persisting>` and `Zerk<Storing>`
        // are one specialization, which is what the alias asserted — and that is
        // what a provider's parameter does too.
        #expect(result.output.output.contains("store: Persisting = Zerk<Persisting>.inject()"))
        #expect(!result.output.output.contains("inject(store:"))
    }
}
