//
//  RethrowsTests.swift
//  Zerk
//

import Testing
@testable import CodegenToolkit

/// Coverage of `rethrows`, and of the effect clause being read as tokens rather
/// than as a substring.
///
/// `rethrows` is not `throws` with extra steps. Widening it costs the caller a
/// `try` on a call site that passes a non-throwing closure — and a `try` needs a
/// throwing context, so the widening propagates up the *caller's* stack. It is
/// preserved wherever the emitted signature can carry it, and widened where it
/// cannot: Swift requires a `rethrows` function to have a throwing function
/// parameter to rethrow from, and the member Zerk emits is not the provider.
@Suite("rethrows")
struct RethrowsTests {

    // MARK: - Reading the effect clause

    @Test("an effect clause is read as tokens, not as a substring", arguments: [
        ("throws", false, ProviderEffects.Throwing.throwing),
        ("rethrows", false, .rethrowing),
        ("async throws", true, .throwing),
        ("async rethrows", true, .rethrowing),
        // A typed throw is a `throws` token carrying a type, and widens.
        ("throws(MyError)", false, .throwing),
        ("async throws(MyError)", true, .throwing),
        ("async", true, .none),
        ("", false, .none),
    ])
    func effectClauseIsTokenized(clause: String, isAsync: Bool, throwing: ProviderEffects.Throwing) {
        // `"rethrows".contains("throws")` is true, so a substring test answers
        // "throws" for a `rethrows` clause by accident rather than by decision.
        let effects = ProviderEffects(from: clause)

        #expect(effects.isAsync == isAsync)
        #expect(effects.throwing == throwing)
    }

    @Test("an absent clause is no effects")
    func absentClauseIsNone() {
        #expect(ProviderEffects(from: nil) == .none)
    }

    // MARK: - Merging

    @Test("merging widens, and rethrows loses to throws")
    func mergingWidens() {
        let rethrowing = ProviderEffects(isAsync: false, throwing: .rethrowing)
        let throwing = ProviderEffects(isAsync: false, throwing: .throwing)
        let asyncOnly = ProviderEffects(isAsync: true, throwing: .none)

        // Once something in the chain throws unconditionally, so does the member.
        #expect(rethrowing.merged(with: throwing).throwing == .throwing)
        #expect(rethrowing.merged(with: .none).throwing == .rethrowing)
        #expect(rethrowing.merged(with: rethrowing).throwing == .rethrowing)
        // Async is an independent axis.
        #expect(rethrowing.merged(with: asyncOnly) == ProviderEffects(isAsync: true, throwing: .rethrowing))
    }

    @Test("rethrows counts as throwing for everything gated on 'can this throw'")
    func rethrowsIsThrowing() {
        let rethrowing = ProviderEffects(isAsync: false, throwing: .rethrowing)

        #expect(rethrowing.isThrowing)
        #expect(rethrowing.isRethrowing)
        #expect(rethrowing.callPrefix == "try ")
        #expect(rethrowing.declarationSuffix == " rethrows")
    }

    // MARK: - Emission

    @Test("a rethrows provider keeps rethrows")
    func rethrowsIsPreserved() throws {
        let source = """
        @Injectable
        struct Mapper {
            @InjectableProviding
            init(transform: () throws -> Int) rethrows {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains(
            "static func mapper(transform: () throws -> Int) rethrows -> Mapper {"))
        #expect(result.output.output.contains(
            "static func inject(transform: () throws -> Int) rethrows -> Mapper {"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("a rethrows static factory keeps rethrows")
    func rethrowsFactoryIsPreserved() throws {
        let source = """
        @Injectable
        struct Mapper {
            @InjectableProviding
            static func make(f: () throws -> Int) rethrows -> Mapper { .init() }
            init() {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains(
            "static func make(f: () throws -> Int) rethrows -> Mapper {"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("async rethrows survives on both axes")
    func asyncRethrowsIsPreserved() throws {
        let source = """
        @Injectable
        struct Mapper {
            @InjectableProviding
            init(transform: () throws -> Int) async rethrows {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains(
            "static func mapper(transform: () throws -> Int) async rethrows -> Mapper {"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    // MARK: - Where it must widen

    @Test("a throwing dependency widens the resolving variant to throws")
    func throwingDependencyWidens() throws {
        // The explicit variant only throws if its closure does, so it keeps
        // `rethrows`. The resolving variant builds `Dep`, which throws outright.
        let source = """
        @Injectable
        struct Dep {
            @InjectableProviding
            init() throws {}
        }

        @Injectable
        struct Consumer {
            @InjectableProviding
            init(dep: Dep, transform: () throws -> Int) rethrows {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains(
            "static func consumer(dep: Dep, transform: () throws -> Int) rethrows -> Consumer {"))
        #expect(result.output.output.contains(
            "static func consumer(transform: () throws -> Int) throws -> Consumer {"))
        #expect(result.output.output.contains(
            "static func inject(transform: () throws -> Int) throws -> Consumer {"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("a signature with nothing left to rethrow from widens")
    func resolvedAwayClosureWidens() throws {
        // Swift refuses `rethrows` on a signature with no throwing function
        // parameter. Here the closure resolves from the graph, so `inject()`
        // takes nothing at all and has to say `throws`.
        let source = """
        @InjectableValue
        var maker: () throws -> Int { { 1 } }

        @Injectable
        struct Mapper {
            @InjectableProviding
            init(maker: () throws -> Int) rethrows {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        // The named member keeps the parameter (defaulted), so it keeps rethrows.
        #expect(result.output.output.contains(
            "static func mapper(maker: () throws -> Int = Zerk<() throws -> Int>.maker) rethrows -> Mapper {"))
        // `inject()` has no parameter left, so it widens.
        #expect(result.output.output.contains("static func inject() throws -> Mapper {"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    // MARK: - Typed throws

    @Test("a typed throw widens to an untyped one")
    func typedThrowsWidens() throws {
        // Restating `E` on the member only works while one error type is in
        // play; two providers in a chain naming different ones leave no single
        // `E` to restate. The concrete type stays the developer's to catch.
        let source = """
        struct MyError: Error {}

        @Injectable
        struct Loader {
            @InjectableProviding
            init() throws(MyError) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("static func loader() throws -> Loader {"))
        #expect(!result.output.output.contains("throws(MyError)"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    // MARK: - The throwing-parameter test

    @Test("a throwing function parameter is recognized", arguments: [
        ("() throws -> Int", true),
        ("(Int) throws -> Void", true),
        ("@escaping () throws -> Int", true),
        ("() async throws -> Int", true),
        // Not throwing, or not a function at all.
        ("() -> Int", false),
        ("Int", false),
        ("ThrowsBox", false),
        // The `throws` is on the *result*, so there is nothing to rethrow from.
        ("() -> (() throws -> Int)", false),
    ])
    func throwingFunctionParameterDetection(typeName: String, expected: Bool) {
        let parameter = ParameterRecord(label: nil, name: "f", typeKey: typeName, typeName: typeName)
        #expect(parameter.isThrowingFunctionType == expected)
    }
}
