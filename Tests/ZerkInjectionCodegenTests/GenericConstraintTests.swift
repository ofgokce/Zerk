//
//  GenericConstraintTests.swift
//  Zerk
//

import Testing
@testable import CodegenToolkit

/// Coverage of generic *constraints* — which of them the generated member has to
/// restate, and which it must not.
///
/// The line runs between the two halves of a member's parameter list, and it is
/// the same line that decides inference. A constraint on the **type**'s
/// parameters is re-derived: `where Injectable == Codec<E>` makes `Codec<E>`
/// well-formed, which is exactly the type's own requirements. A constraint on
/// the **provider**'s parameters is not, because nothing in the return type
/// mentions them — so it has to be carried across, or the generated file calls a
/// provider whose requirements it does not satisfy.
@Suite("Generic constraints")
struct GenericConstraintTests {

    // MARK: - The type's own constraints are re-derived, not restated

    @Test("an inline constraint and a where clause are the same declaration", arguments: [
        "struct Foo<A: Hashable, B>",
        "struct Foo<A, B> where A: Hashable",
    ])
    func inlineAndWhereClauseAgree(declaration: String) throws {
        // Zerk reads parameter *names* only, so the two spellings are literally
        // indistinguishable by the time codegen sees them.
        let source = """
        @Injectable
        \(declaration) {
            @InjectableProviding
            init(a: A, b: B) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains(
            "static func foo<A, B>(a: A, b: B) -> Foo<A, B> where Injectable == Foo<A, B> {"))
        // Restating it would be redundant, and would have to be re-spelled for
        // every constraint form Swift allows.
        #expect(!result.output.output.contains("A: Hashable"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("every type-level constraint form survives the round trip", arguments: [
        "struct T<A: Hashable & Codable, B>",
        "struct T<A: Collection, B> where A.Element: Hashable",
        "struct T<A: Collection, B> where A.Element == B",
    ])
    func typeLevelConstraintFormsCompile(declaration: String) throws {
        // The attribute has to start its own line: `CompileFixture` strips Zerk
        // attributes by line prefix before handing the fixture to swiftc.
        let source = """
        @Injectable
        \(declaration) {
            @InjectableProviding
            init(a: A, b: B) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)
        #expect(result.diagnostics.isEmpty)

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    // MARK: - The provider's own constraints are carried across

    @Test("a constrained provider generic keeps its requirement")
    func providerGenericKeepsItsConstraint() throws {
        // Nothing re-derives `Z: Numeric`: `Z` appears nowhere in the return
        // type, which is the same reason nothing can infer it.
        let source = """
        @Injectable
        struct PlainInit {
            @InjectableProviding
            init<Z: Numeric>(z: Z) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains(
            "static func plainInit<Z>(z: Z) -> PlainInit where Z: Numeric {"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("a static factory's constrained generic keeps its requirement")
    func factoryGenericKeepsItsConstraint() throws {
        let source = """
        @Injectable
        struct PlainFactory {
            @InjectableProviding
            static func make<Z: Numeric>(z: Z) -> PlainFactory { .init(z: z) }
            init<Z: Numeric>(z: Z) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains(
            "static func make<Z>(z: Z) -> PlainFactory where Z: Numeric {"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("a provider constraint joins the key's binding rather than replacing it")
    func providerConstraintJoinsTheKeyBinding() throws {
        // Both requirements belong on one member: the key binds the type's
        // parameters, the provider's own requirement rides alongside.
        let source = """
        @Injectable
        struct Adder<A: Hashable> {
            @InjectableProviding
            init<Z: Numeric>(a: A, z: Z) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains(
            "static func adder<A, Z>(a: A, z: Z) -> Adder<A> where Injectable == Adder<A>, Z: Numeric {"))
        // The type's half is still re-derived, not restated.
        #expect(!result.output.output.contains("A: Hashable"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("a provider's own where clause is carried verbatim")
    func providerWhereClauseIsCarriedVerbatim() throws {
        // Zerk reads syntax and cannot resolve a requirement, so an associated
        // type has to arrive at the generated file spelled as written.
        let source = """
        @Injectable
        struct AssocProv {
            @InjectableProviding
            init<Z: Collection>(z: Z) where Z.Element: Hashable {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains(
            "static func assocProv<Z>(z: Z) -> AssocProv where Z: Collection, Z.Element: Hashable {"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("both halves at once, on a generic type")
    func inheritanceAndWhereClauseTogether() throws {
        let source = """
        @Injectable
        struct Both<A: Hashable> {
            @InjectableProviding
            init<Z: Collection>(a: A, z: Z) where Z.Element == A {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains(
            "where Injectable == Both<A>, Z: Collection, Z.Element == A {"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    // MARK: - The @Injectable declaration form

    @Test("a function's constraint beyond its produced type is carried")
    func declarationFormCarriesItsOwnConstraint() throws {
        // `Box<X, Y>` declares no requirements of its own, so `where Injectable
        // == Box<X, Y>` re-derives nothing and the function's `X: Hashable` has
        // to travel.
        let source = """
        struct Box<X, Y> { init(x: X, y: Y) {} }

        @Injectable(typeNamed: true)
        func makeBox<X: Hashable, Y>(x: X, y: Y) -> Box<X, Y> { .init(x: x, y: y) }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains(
            "static func box<X, Y>(x: X, y: Y) -> Box<X, Y> where Injectable == Box<X, Y>, X: Hashable {"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("the forwarding thunk carries the constraint too")
    func thunkCarriesTheConstraint() throws {
        // The thunk is a file-scope function calling the declaration directly.
        // It is outside the extension, so it has no `Injectable` to re-derive
        // anything from — every requirement has to be on it explicitly.
        let source = """
        struct Box<X, Y> { init(x: X, y: Y) {} }

        @Injectable(typeNamed: true)
        func makeBox<X: Hashable, Y>(x: X, y: Y) -> Box<X, Y> { .init(x: x, y: y) }
        """

        let output = CompileFixture.generate(source: source)

        #expect(output.contains(
            "private func _$zerk_provider_makeBox<X, Y>(x: X, y: Y) -> Box<X, Y> where X: Hashable {"))
    }

    // MARK: - Nothing changes where there is no constraint

    @Test("an unconstrained provider generic emits no where clause")
    func unconstrainedProviderGenericIsUnchanged() throws {
        let source = """
        @Injectable
        struct Pair<X, Y> {
            @InjectableProviding
            init<Z>(x: X, y: Y, z: Z) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains(
            "static func pair<X, Y, Z>(x: X, y: Y, z: Z) -> Pair<X, Y> where Injectable == Pair<X, Y> {"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }
}
