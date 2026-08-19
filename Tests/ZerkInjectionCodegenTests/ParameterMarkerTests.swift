//
//  ParameterMarkerTests.swift
//  Zerk
//

import Testing
@testable import CodegenToolkit

/// Coverage of the parameter markers that shape resolution: `@noninjected`,
/// `@injectable`, and the bubbling `@injected` now does.
///
/// The through-line is that a dependency's own provider may still need
/// arguments. Those bubble up to whatever is resolving it, and `@injectable` is
/// how a member says one of its existing parameters already supplies one —
/// without it, the same value would be declared twice.
@Suite("Parameter markers")
struct ParameterMarkerTests {

    private static let graph = """
    struct Value {}

    @Injectable
    final class Foo {
        @InjectableProviding
        init(value: Value) {}
    }
    """

    // MARK: - @injected bubbling

    /// The shapes `@injected` refuses, and one it must not.
    ///
    /// The `inout` refusal was a `hasPrefix("inout")` on the rendered type, so a
    /// type *named* `inoutBuffer` was reported as an `inout` parameter — naming
    /// something the developer had not written, with renaming the type as the
    /// only remedy. It reads the specifier off the tree now, which is what
    /// `nominalNames` and `mentionedGenericParameters` already say about
    /// substring tests.
    @Test("@injected refuses the shapes it cannot resolve, and only those",
          arguments: [
            ("inout Serving", true),
            ("Serving...", true),
            ("inoutBuffer", false),
            ("Serving", false),
          ])
    func refusedParameterShapes(type: String, isRefused: Bool) {
        let result = CompileFixture.generateWithResolution(source: """
        protocol Serving {}

        @Injectable<Serving>
        struct Live: Serving {}

        @Injectable<inoutBuffer>
        struct inoutBuffer {}

        final class Screen {
            init(@injected s: \(type), title: String) {}
        }
        """)

        let refusals = result.diagnostics.filter {
            $0.message.contains("cannot be applied to")
        }
        #expect(refusals.isEmpty != isRefused,
                "\(type): \(result.diagnostics.map(\.message))")
    }

    @Test("a parametric dependency bubbles into the overload")
    func injectedBubbles() {
        let source = """
        \(Self.graph)

        final class Bar {
            init(@injected foo: Foo, label: String) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("convenience init(label: String, value: Value)"))
        #expect(result.output.output.contains("self.init(foo: Zerk<Foo>.inject(value: value), label: label)"))
    }

    // MARK: - @injectable

    @Test("@injectable feeds one parameter to both the member and its dependency")
    func injectableSharesAParameter() throws {
        let source = """
        \(Self.graph)

        final class Bar {
            init(@injected foo: Foo, @injectable value: Value) {}
        }
        """

        let result = try CompileFixture.run(source: source)

        #expect(result.generated.contains("convenience init(value: Value)"))
        #expect(result.generated.contains("self.init(foo: Zerk<Foo>.inject(value: value), value: value)"))
        // One `value`, not two.
        #expect(!result.generated.contains("value: Value, value: Value"))

        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(result.didCompile, Comment(rawValue: result.compilerOutput))
    }

    @Test("@injectable works on a provider alongside @autoinjected")
    func injectableWorksOnProviders() throws {
        let source = """
        \(Self.graph)

        @Injectable
        final class Bar {
            @InjectableProviding
            init(@autoinjected foo: Foo, @injectable value: Value) {}
        }
        """

        let result = try CompileFixture.run(source: source)

        #expect(result.generated.contains("static func inject(value: Value) -> Bar"))
        #expect(result.generated.contains("bar(foo: Zerk<Foo>.inject(value: value), value: value)"))

        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(result.didCompile, Comment(rawValue: result.compilerOutput))
    }

    @Test("a name that differs does not match, so the requirement bubbles separately")
    func mismatchedNameDoesNotShare() {
        // Matched by name *and* type, the same rule injectable values follow.
        let source = """
        \(Self.graph)

        final class Bar {
            init(@injected foo: Foo, @injectable config: Value) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("convenience init(config: Value, value: Value)"))
    }

    // MARK: - Collisions

    @Test("an unmarked parameter colliding with a bubbled requirement is an error")
    func collisionOnOverloadIsAnError() {
        let source = """
        \(Self.graph)

        final class Bar {
            init(@injected foo: Foo, value: Value) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.contains {
            $0.severity == .error
                && $0.message.contains("collides with this member's own 'value' parameter")
                && $0.message.contains("Mark it @injectable")
        })
    }

    @Test("the same collision on a provider is an error too")
    func collisionOnProviderIsAnError() {
        let source = """
        \(Self.graph)

        @Injectable
        final class Bar {
            @InjectableProviding
            init(@autoinjected foo: Foo, value: Value) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.contains {
            $0.severity == .error
                && $0.message.contains("collides with 'Bar's own 'value' parameter")
                && $0.message.contains("Mark it @injectable")
        })
    }

    // MARK: - Ordering and combining

    @Test("bubbled parameters go after the member's own, on both paths")
    func bubbledParametersGoLast() {
        // The member's own parameters keep their relative order and everything
        // hoisted from the graph is grouped after them — the same rule whether
        // the resolution came from @injected or @autoinjected.
        let source = """
        \(Self.graph)

        final class Overload {
            init(first: String, @injected foo: Foo, last: String) {}
        }

        @Injectable
        final class Provider {
            @InjectableProviding
            init(first: String, @autoinjected foo: Foo, last: String) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("convenience init(first: String, last: String, value: Value)"))
        #expect(result.output.output.contains("static func inject(first: String, last: String, value: Value) -> Provider"))
    }

    @Test("bubbled parameters follow the order of the parameters that pulled them in")
    func bubbledParametersFollowSourceOrder() {
        let source = """
        struct Value {}
        struct Extra {}

        @Injectable
        final class Foo {
            @InjectableProviding
            init(value: Value) {}
        }

        @Injectable
        final class Qux {
            @InjectableProviding
            init(extra: Extra) {}
        }

        final class Bar {
            init(@injected foo: Foo, mid: String, @injected qux: Qux) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("convenience init(mid: String, value: Value, extra: Extra)"))
    }

    @Test("two dependencies needing the same name and type share one parameter")
    func sameNameSameTypeIsShared() throws {
        let source = """
        struct Value {}

        @Injectable
        final class FooA {
            @InjectableProviding
            init(value: Value) {}
        }

        @Injectable
        final class FooB {
            @InjectableProviding
            init(value: Value) {}
        }

        @Injectable
        final class Consumer {
            @InjectableProviding
            init(@autoinjected a: FooA, @autoinjected b: FooB) {}
        }
        """

        let result = try CompileFixture.run(source: source)

        #expect(result.generated.contains("static func inject(value: Value) -> Consumer"))
        #expect(result.generated.contains("a: Zerk<FooA>.inject(value: value)"))
        #expect(result.generated.contains("b: Zerk<FooB>.inject(value: value)"))

        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(result.didCompile, Comment(rawValue: result.compilerOutput))
    }

    @Test("the same name with different types keeps the label and splits the inner name")
    func sameNameDifferentTypesIsDisambiguated() throws {
        // Emitting both as `value` is `invalid redeclaration of 'value'`, so the
        // inner names are suffixed with the parameter that pulled each one in.
        let source = """
        struct ValueA {}
        struct ValueB {}

        @Injectable
        final class FooA {
            @InjectableProviding
            init(value: ValueA) {}
        }

        @Injectable
        final class FooB {
            @InjectableProviding
            init(value: ValueB) {}
        }

        @Injectable
        final class Consumer {
            @InjectableProviding
            init(@autoinjected a: FooA, @autoinjected b: FooB) {}
        }
        """

        let result = try CompileFixture.run(source: source)

        #expect(result.generated.contains("static func inject(value valueA: ValueA, value valueB: ValueB) -> Consumer"))
        #expect(result.generated.contains("a: Zerk<FooA>.inject(value: valueA)"))
        #expect(result.generated.contains("b: Zerk<FooB>.inject(value: valueB)"))

        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(result.didCompile, Comment(rawValue: result.compilerOutput))
    }

    @Test("a bubbled name clashing with an own parameter of another type is renamed")
    func bubbledNameClashingWithOwnParameterIsRenamed() throws {
        // `value: String` is the member's; `value: Value` is FooA's. Same name,
        // different types, so only the bubbled one can move.
        let source = """
        struct Value {}

        @Injectable
        final class Foo {
            @InjectableProviding
            init(value: Value) {}
        }

        @Injectable
        final class Consumer {
            @InjectableProviding
            init(@autoinjected foo: Foo, @noninjected value: String) {}
        }
        """

        let result = try CompileFixture.run(source: source)

        #expect(result.generated.contains("value: String"))
        #expect(result.generated.contains("value valueFoo: Value"))
        #expect(result.generated.contains("Zerk<Foo>.inject(value: valueFoo)"))

        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(result.didCompile, Comment(rawValue: result.compilerOutput))
    }

    // MARK: - @noninjected

    @Test("@noninjected keeps a resolvable parameter caller-supplied")
    func nonInjectedOptsOut() {
        let source = """
        @InjectableValue
        var retries: Int { 3 }

        @Injectable
        final class Consumer {
            @InjectableProviding
            init(@noninjected retries: Int) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("static func inject(retries: Int) -> Consumer"))
        #expect(!result.output.output.contains("retries: Int = Zerk<Int>.retries"))
    }

    @Test("without the marker the same parameter resolves")
    func withoutNonInjectedItResolves() {
        let source = """
        @InjectableValue
        var retries: Int { 3 }

        @Injectable
        final class Consumer {
            @InjectableProviding
            init(retries: Int) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.output.output.contains("static func inject() -> Consumer"))
        #expect(result.output.output.contains("retries: Int = Zerk<Int>.retries"))
    }

    @Test("@noninjected alongside @autoinjected is accepted silently")
    func nonInjectedIsRedundantButQuiet() {
        // Explicit mode already excludes everything unmarked, so this says
        // nothing new — but stating every parameter's intent is a fair style.
        let source = """
        @InjectableValue
        var retries: Int { 3 }

        \(Self.graph)

        @Injectable
        final class Consumer {
            @InjectableProviding
            init(@autoinjected foo: Foo, @noninjected retries: Int) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(!result.diagnostics.contains { $0.message.contains("@noninjected") })
    }

    @Test("marking one parameter both ways is an error")
    func contradictoryMarkersAreRejected() {
        let source = """
        @InjectableValue
        var retries: Int { 3 }

        @Injectable
        final class Consumer {
            @InjectableProviding
            init(@autoinjected @noninjected retries: Int) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.contains {
            $0.severity == .error
                && $0.message.contains("marked both @autoinjected and @noninjected")
        })
    }

    // MARK: - Global functions

    @Test("@injected on a global function generates a file-scope overload")
    func globalFunctionOverload() throws {
        // A type's members are collected by walking its member block; a global
        // has no type to walk, so it used to be skipped in silence — the one
        // outcome an explicit marker exists to rule out.
        let source = """
        @Injectable
        final class Logger { init() {} }

        func audit(@injected logger: Logger, label: String) {}
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        // File-scope, so no `extension` wrapper and no indent.
        #expect(result.output.output.contains("""
        nonisolated func audit(label: String) {
            audit(logger: Zerk<Logger>.inject(), label: label)
        }
        """))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("a global overload keeps its return type and isolation")
    func globalFunctionReturnAndIsolation() {
        let output = CompileFixture.generate(source: """
        @Injectable
        final class Logger { init() {} }

        @MainActor
        func caption(@injected logger: Logger, label: String) -> String { label }
        """)

        #expect(output.contains("@MainActor func caption(label: String) -> String {"))
    }

    @Test("a local function is not a global", arguments: [
        // Inside an accessor…
        """
        var accessor: Int {
            func local(@injected logger: Logger) {}
            return 0
        }
        """,
        // …and inside a function body.
        """
        func outer() {
            func local(@injected logger: Logger) {}
        }
        """,
    ])
    func localFunctionsAreNotCollected(declaration: String) {
        // Nothing outside the file can call an overload of a local function, so
        // "top level" is read from the tree rather than from an empty type
        // stack — which is also empty inside a global accessor.
        let output = CompileFixture.generate(source: """
        @Injectable
        final class Logger { init() {} }

        \(declaration)
        """)

        #expect(!output.contains("func local("))
    }

    @Test("global overloads obey the same constraints as members", arguments: [
        ("private func hidden(@injected logger: Logger) {}", "at least internal"),
        ("func generic<T>(@injected logger: Logger, t: T) {}", "generic types or generic members"),
    ])
    func globalConstraints(declaration: String, message: String) {
        let result = CompileFixture.generateWithResolution(source: """
        @Injectable
        final class Logger { init() {} }

        \(declaration)
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error && $0.message.contains(message)
        })
    }

    @Test("two globals generating one overload are reported")
    func globalOverloadCollision() {
        let result = CompileFixture.generateWithResolution(source: """
        @Injectable
        final class Logger { init() {} }

        @Injectable
        final class Other { init() {} }

        func dup(@injected logger: Logger, x: Int) {}
        func dup(@injected other: Other, x: Int) {}
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error
                && $0.message.contains("Two @injected global functions generate the same overload")
        })
    }
}
