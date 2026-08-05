//
//  GenericEmissionTests.swift
//  Zerk
//

import Testing
@testable import CodegenToolkit

/// Coverage of the members Zerk emits for a generic key.
///
/// The shape is one unconstrained `extension Zerk` whose members bind the key
/// themselves:
///
/// ```swift
/// extension Zerk {
///     static func cache<E>(serializer: Serializer<E> = Zerk<Serializer<E>>.inject())
///     -> Cache<E> where Injectable == Cache<E> { … }
/// }
/// ```
///
/// The header cannot bind it — `extension Zerk<Cache<E>>` has no `E` to name —
/// and a member cannot be a `static var`, since properties take no generic
/// parameters. Every case here asserts the emitted text *and* type-checks it,
/// because a `where` clause that reads correctly can still fail to compile.
@Suite("Generic emission")
struct GenericEmissionTests {

    @Test("a generic key emits an unconstrained extension with bound members")
    func genericKeyEmitsBoundMembers() throws {
        let source = """
        @Injectable
        struct Cache<E> {
            @InjectableProviding
            init() {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("extension Zerk {"))
        #expect(!result.output.output.contains("extension Zerk<Cache"))
        #expect(result.output.output.contains(
            "nonisolated static func cache<E>() -> Cache<E> where Injectable == Cache<E> {"))
        #expect(result.output.output.contains(
            "nonisolated static func inject<E>() -> Cache<E> where Injectable == Cache<E> {"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("an argument-free generic member is still a function")
    func genericMembersAreNeverProperties() {
        // A concrete key gets `static var cache: Cache` here. A generic one
        // cannot: properties take no generic parameters, so the `Zerk<Cache<String>>.cache`
        // spelling is not available and `inject()` calls the function.
        let source = """
        @Injectable
        struct Cache<E> {
            @InjectableProviding
            init() {}
        }
        """

        let output = CompileFixture.generate(source: source)

        #expect(!output.contains("static var cache"))
        #expect(output.contains("        cache()"))
    }

    @Test("every parameter of the type reaches the member")
    func arityIsCarriedThrough() throws {
        let source = """
        @Injectable
        struct Store<K, V> {
            @InjectableProviding
            init() {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains(
            "static func store<K, V>() -> Store<K, V> where Injectable == Store<K, V> {"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("a generic member resolves a concrete dependency into a default")
    func concreteDependencyIsDefaulted() throws {
        let source = """
        @Injectable
        struct Logger {
            @InjectableProviding
            init() {}
        }

        @Injectable
        struct Cache<E> {
            @InjectableProviding
            init(logger: Logger) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains(
            "static func cache<E>(logger: Logger = Zerk<Logger>.inject()) -> Cache<E> where Injectable == Cache<E> {"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("a generic member resolves a dependency through its own parameter")
    func genericDependencyThreadsTheParameter() throws {
        // The shape lookup is what finds `Serializer<E>`'s registration, and the
        // default argument is what makes it legal — a default may name the
        // function's own generic parameter.
        let source = """
        @Injectable
        struct Serializer<E> {
            @InjectableProviding
            init() {}
        }

        @Injectable
        struct Cache<E> {
            @InjectableProviding
            init(serializer: Serializer<E>) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains(
            "static func cache<E>(serializer: Serializer<E> = Zerk<Serializer<E>>.inject()) -> Cache<E> where Injectable == Cache<E> {"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("a concrete consumer resolves a specialization of a generic key")
    func concreteConsumerResolvesASpecialization() throws {
        // This is what the shape lookup buys: `Cache<String>` is not a key any
        // declaration registered, and matching it to `Cache<#0>` is what turns
        // the parameter from caller-supplied into resolved.
        let source = """
        @Injectable
        struct Cache<E> {
            @InjectableProviding
            init() {}
        }

        @Injectable
        struct Screen {
            @InjectableProviding
            init(cache: Cache<String>) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains(
            "static func screen(cache: Cache<String> = Zerk<Cache<String>>.inject()) -> Screen {"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("the type's own constraints are not repeated on the member")
    func constraintsAreNotRepeated() throws {
        // `where Injectable == Codec<E>` re-derives `E: Codable` from the
        // same-type requirement, and a specialization that violates it still
        // fails at the call site with Codable's own message. Repeating the
        // constraint would be work with nothing reading it.
        let source = """
        @Injectable
        struct Codec<E: Codable> {
            @InjectableProviding
            init() {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.output.output.contains(
            "static func codec<E>() -> Codec<E> where Injectable == Codec<E> {"))
        #expect(!result.output.output.contains("<E: Codable>"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("a bare type parameter is caller-supplied, never resolved")
    func bareTypeParameterIsNeverResolved() throws {
        // The trap: a module type spelled like the parameter. Inside the member
        // `E` is the parameter and shadows that type, so resolving `item` to
        // `Zerk<E>.inject()` would be wrong — and does not even compile
        // ("cannot use default expression for inference of 'E'"). Nothing
        // registers a bare parameter, so it bubbles to the caller.
        let source = """
        @Injectable
        struct E {
            @InjectableProviding
            init() {}
        }

        @Injectable
        struct Holder<E> {
            @InjectableProviding
            init(item: E) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(!result.output.output.contains("item: E = Zerk<E>.inject()"))
        #expect(result.output.output.contains(
            "static func holder<E>(item: E) -> Holder<E> where Injectable == Holder<E> {"))
        // Required, so it bubbles onto inject() rather than disappearing.
        #expect(result.output.output.contains(
            "static func inject<E>(item: E) -> Holder<E> where Injectable == Holder<E> {"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    // MARK: - A generic type under a concrete key

    @Test("a concrete key keeps its header and takes a generic member")
    func concreteKeyTakesAGenericMember() throws {
        // The other mode: the key erases the parameters, so the member recovers
        // them from its arguments and needs no where clause — an ordinary
        // generic method on a concrete extension.
        let source = """
        protocol Boxable { associatedtype X; associatedtype Y }

        @Injectable<any Boxable>
        struct Box<X, Y>: Boxable {
            @InjectableProviding
            init(_ x: X, _ y: Y) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("extension Zerk<any Boxable> {"))
        #expect(result.output.output.contains(
            "static func box<X, Y>(_ x: X, _ y: Y) -> any Boxable {"))
        // No where clause: the header already bound the key.
        #expect(!result.output.output.contains("where Injectable == any Boxable"))
        #expect(result.output.output.contains(
            "static func inject<X, Y>(_ x: X, _ y: Y) -> any Boxable {"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("a concrete key is interjectable even when its member is generic")
    func concreteKeyWithGenericMemberIsInterjectable() {
        // The point hangs off the *key*, and this key is concrete — so unlike a
        // generic key, this one keeps its guard and its point.
        let source = """
        protocol Boxable { associatedtype X; associatedtype Y }

        @Injectable<any Boxable>
        struct Box<X, Y>: Boxable {
            @InjectableProviding
            init(_ x: X, _ y: Y) {}
        }
        """

        let output = CompileFixture.generate(source: source)

        #expect(output.contains("extension Zerk<any Boxable>.Interjection"))
        #expect(output.contains("if let interjected = _$interjected(for: \\.`box`)"))
    }

    @Test("the @Injected overload binds the erased parameters")
    func erasedKeyOverloadIsGeneric() throws {
        let source = """
        protocol Boxable { associatedtype X; associatedtype Y }

        @Injectable<any Boxable>
        struct Box<X, Y>: Boxable {
            @InjectableProviding
            init(_ x: X, _ y: Y) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.output.output.contains("macro Injected<X, Y>(_: X, _: Y)"))
    }

    // MARK: - A parameterized existential key

    @Test("parameterized: true applies the type's parameters to the key")
    func parameterizedKeyCarriesTheParameters() throws {
        // The third mode. The key is written `any Boxable` because an attribute
        // cannot name `X`/`Y` — it is resolved outside the declaration's scope —
        // and `parameterized: true` says to apply them.
        let source = """
        protocol Boxable<X, Y> { associatedtype X; associatedtype Y }

        @Injectable<any Boxable>(parameterized: true)
        struct Box<X, Y>: Boxable {
            @InjectableProviding
            init(_ x: X, _ y: Y) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains(
            "static func box<X, Y>(_ x: X, _ y: Y) -> any Boxable<X, Y> where Injectable == any Boxable<X, Y> {"))
        #expect(result.output.output.contains(
            "static func inject<X, Y>(_ x: X, _ y: Y) -> any Boxable<X, Y> where Injectable == any Boxable<X, Y> {"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("a parameterized existential key gates its extension on availability")
    func parameterizedKeyIsAvailabilityGated() {
        // Parameterized existentials are iOS 16 / macOS 13. The plugin cannot
        // read the target's deployment version — the same reason
        // ZerkSettings.json exists — so the attribute is emitted always.
        let source = """
        protocol Boxable<X, Y> { associatedtype X; associatedtype Y }

        @Injectable<any Boxable>(parameterized: true)
        struct Box<X, Y>: Boxable {
            @InjectableProviding
            init(_ x: X, _ y: Y) {}
        }

        @Injectable
        struct Logger {
            @InjectableProviding
            init() {}
        }
        """

        let output = CompileFixture.generate(source: source)

        #expect(output.contains(
            "@available(iOS 16.0, macOS 13.0, macCatalyst 16.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)\nextension Zerk {"))
        // Only the extension that needs it.
        #expect(!output.contains("*)\nextension Zerk<Logger>"))
    }

    @Test("erasing and parameterizing are different keys for the same attribute")
    func parameterizedChangesTheKey() {
        // Without `parameterized:` the same attribute means the opposite — erase
        // the parameters into a plain `any Boxable` — which is why it has to be
        // asked for rather than inferred.
        let erasing = CompileFixture.generate(source: """
        protocol Boxable<X, Y> { associatedtype X; associatedtype Y }

        @Injectable<any Boxable>
        struct Box<X, Y>: Boxable {
            @InjectableProviding
            init(_ x: X, _ y: Y) {}
        }
        """)

        #expect(erasing.contains("extension Zerk<any Boxable> {"))
        #expect(erasing.contains("-> any Boxable {"))
        #expect(!erasing.contains("any Boxable<X, Y>"))
    }

    @Test("a specialization of a parameterized key resolves as a dependency")
    func parameterizedKeyResolvesAsADependency() throws {
        // The key is a shape like any other generic key, so `any Boxable<Int,
        // String>` finds it the same way `Cache<String>` finds `Cache<#0>`.
        let source = """
        protocol Boxable<X, Y> { associatedtype X; associatedtype Y }

        @Injectable<any Boxable>(parameterized: true)
        struct Box<X, Y>: Boxable {
            @InjectableProviding
            init(_ x: X, _ y: Y) {}
        }

        @Injectable
        struct Screen {
            @InjectableProviding
            init(box: any Boxable<Int, String>) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        // Not defaulted: the provider's own arguments bubble up, so `Screen`
        // takes the box rather than resolving it argument-free.
        #expect(result.output.output.contains("box: any Boxable<Int, String>"))
    }

    // MARK: - Providers with generic parameters of their own

    @Test("a generic initializer on a non-generic type is a generic member")
    func genericInitializerOnConcreteType() throws {
        // The parameters come from the *member*, not the key, and are inferred
        // from its arguments — the same shape as an erasing key, reached from
        // the other direction.
        let source = """
        @Injectable
        struct Box {
            init<X, Y>(x: X, y: Y) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("extension Zerk<Box> {"))
        #expect(result.output.output.contains("static func box<X, Y>(x: X, y: Y) -> Box {"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("a provider may add parameters to the ones its key binds", arguments: [
        // Unmarked: adopted as the sole initializer.
        """
        @Injectable
        struct Box<X, Y> {
            init<Z>(x: X, y: Y, z: Z) {}
        }
        """,
        // Marked, alongside another initializer.
        """
        @Injectable
        struct Box<X, Y> {
            init() {}
            @InjectableProviding
            init<Z>(x: X, y: Y, z: Z) {}
        }
        """,
    ])
    func providerAddsItsOwnParameters(_ source: String) throws {
        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        // The type's first, then the provider's own.
        #expect(result.output.output.contains(
            "static func box<X, Y, Z>(x: X, y: Y, z: Z) -> Box<X, Y> where Injectable == Box<X, Y> {"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("a generic static factory is emitted like any other provider")
    func genericStaticFactory() throws {
        let source = """
        @Injectable
        struct Box {
            @InjectableProviding
            static func make<X, Y>(x: X, y: Y) -> Box { .init() }
            init() {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("static func make<X, Y>(x: X, y: Y) -> Box {"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("a member parameter never binds a module type of the same name")
    func memberParameterDoesNotBindAModuleType() throws {
        // The scope a parameter is read in has to include the *member's* own
        // parameters, not just the type's. Without that, `x: X` here resolves
        // against the module's `struct X` — which the member shadows.
        let source = """
        @Injectable
        struct X {
            @InjectableProviding
            init() {}
        }

        @Injectable
        struct Box {
            init<X, Y>(x: X, y: Y) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(!result.output.output.contains("x: X = Zerk<X>.inject()"))
        #expect(result.output.output.contains("static func box<X, Y>(x: X, y: Y) -> Box {"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("a generic member carries no interjection guard or point")
    func genericMembersAreNotYetInterjectable() {
        // A point cannot be declared for a generic key — `extension
        // Zerk<Cache<E>>.Interjection` is "cannot find type 'E' in scope" — so
        // the member carries no guard either. The concrete key alongside it
        // keeps both, which is what makes this a gap rather than a regression.
        let source = """
        @Injectable
        struct Cache<E> {
            @InjectableProviding
            init() {}
        }

        @Injectable
        struct Logger {
            @InjectableProviding
            init() {}
        }
        """

        let output = CompileFixture.generate(source: source)

        #expect(!output.contains("extension Zerk<Cache<E>>.Interjection"))
        #expect(!output.contains("\\.`cache`"))
        #expect(output.contains("extension Zerk<Logger>.Interjection"))
        #expect(output.contains("\\.`logger`"))
    }

    @Test("an @Injected overload binds only the parameters its signature names")
    func macroOverloadBindsWhatItNames() throws {
        // `seed: Int` mentions no parameter of the key, so the declaration stays
        // plain — binding `E` here would be "generic parameter not used in
        // function signature".
        let source = """
        @Injectable
        struct Cache<E> {
            @InjectableProviding
            init(seed: Int) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.output.output.contains("macro Injected(seed: Int)"))
        #expect(!result.output.output.contains("macro Injected<E>(seed: Int)"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("an @Injected overload is generic when its arguments are")
    func macroOverloadIsGenericWhenItsArgumentsAre() throws {
        let source = """
        @Injectable
        struct Holder<E> {
            @InjectableProviding
            init(item: E) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.output.output.contains("macro Injected<E>(item: E)"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }

    @Test("a concrete registration and a generic one coexist")
    func concreteAndGenericCoexist() throws {
        // Swift picks the concrete overload at the call site, and `KeyIndex`
        // agrees — so both members are emitted and neither is ambiguous.
        let source = """
        @Injectable
        struct Cache<E> {
            @InjectableProviding
            init() {}
        }

        @Injectable<Cache<String>>
        struct StringCache: Cache<String> {
            @InjectableProviding
            init() {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.output.output.contains("extension Zerk {"))
        #expect(result.output.output.contains("extension Zerk<Cache<String>> {"))
        #expect(result.diagnostics.allSatisfy { $0.severity != .error })
    }
}
