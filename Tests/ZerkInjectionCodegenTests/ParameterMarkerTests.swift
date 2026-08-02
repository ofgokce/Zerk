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
        @Injectable
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
        @Injectable
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
        @Injectable
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
        @Injectable
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
}
