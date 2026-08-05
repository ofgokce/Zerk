//
//  GenericRefusalTests.swift
//  Zerk
//

import Testing
@testable import CodegenToolkit
import SharedToolkit

/// Coverage of what Zerk does when a registered declaration is generic.
///
/// Before these, a generic `@Injectable` was collected under its bare name and
/// silently produced `extension Zerk<Cache>` — a reference to a generic type
/// with no arguments, so the *generated* file failed to compile and the
/// developer was pointed at code they had not written. Codegen exited zero.
///
/// The cases here pin the two halves of the fix: the refusal is reported at the
/// developer's own declaration, and nothing unspellable reaches the output.
/// Every message is also raised by the matching macro, from ``GenericRefusal``,
/// so the two surfaces cannot drift.
@Suite("Generic refusals")
struct GenericRefusalTests {

    // MARK: - Types

    @Test("a generic injectable type is refused, not emitted")
    func genericInjectableTypeIsRefused() {
        let source = """
        @Injectable
        struct Cache<E> {
            @InjectableProviding
            init() {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.contains {
            $0.severity == .error
                && $0.message.contains("'Cache' is generic")
                && $0.message.contains("would leave 'E' unbound")
        })
        // The shape that used to come out.
        #expect(!result.output.output.contains("extension Zerk<Cache>"))
        #expect(!result.output.output.contains("-> Cache {"))
    }

    @Test("the refusal names every parameter")
    func refusalNamesEveryParameter() {
        let source = """
        @Injectable
        struct Store<K, V> {
            @InjectableProviding
            init() {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.contains { $0.message.contains("'K' and 'V' unbound") })
    }

    @Test("@Singleton on a generic type is refused for its own reason")
    func genericSingletonGetsItsOwnMessage() {
        // This one stays refused however far generic support goes: a singleton's
        // storage is a static stored property, which Swift does not allow in a
        // generic type.
        let source = """
        @Singleton
        @Injectable
        final class Registry<E> {
            @InjectableProviding
            init() {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.contains {
            $0.severity == .error
                && $0.message.contains("@Singleton cannot be applied to the generic type 'Registry'")
                && $0.message.contains("static stored property")
        })
        // Not the general message — a reader needs the reason that will outlast
        // the others.
        #expect(!result.diagnostics.contains { $0.message.contains("'Registry' is generic, which @Injectable") })
    }

    // MARK: - Members

    @Test("a generic provider function is refused")
    func genericProvidingFunctionIsRefused() {
        let source = """
        protocol Boxing {}
        struct Box<E>: Boxing {}

        @Injectable<Boxing>
        struct BoxMaker: Boxing {
            @InjectableProviding
            static func make<E>() -> Box<E> { .init() }
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.contains {
            $0.severity == .error
                && $0.message.contains("@InjectableProviding cannot be applied to the generic function 'make'")
        })
        #expect(!result.output.output.contains("Box<E>"))
    }

    @Test("a generic injectable value function is refused")
    func genericInjectableValueFunctionIsRefused() {
        let source = """
        struct Box<E> {}

        enum Values {
            @InjectableValue
            static func boxed<E>() -> Box<E> { .init() }
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.contains {
            $0.severity == .error
                && $0.message == GenericRefusal.injectableValueFunction
        })
        #expect(!result.output.output.contains("extension Zerk<Box<E>>"))
    }

    @Test("a swept generic value is skipped in silence")
    func sweptGenericValueIsSkippedSilently() {
        // The sweep is a statement about the type, not a promise about every
        // member, so a member it cannot take is dropped rather than reported —
        // the same rule the property sweep follows. Only an annotation is a
        // promise worth breaking loudly.
        let source = """
        struct Box<E> {}

        @InjectableValues
        enum Values {
            static func boxed<E>() -> Box<E> { .init() }
            static var limit: Int { 7 }
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(!result.output.output.contains("Box<E>"))
        // The rest of the sweep still lands.
        #expect(result.output.output.contains("static var limit: Int"))
    }

    // MARK: - Blast radius

    @Test("refusing one type leaves the rest of the module generated")
    func refusingOneTypeLeavesTheRestGenerated() {
        // `collectType` returns early for the generic type. That must drop only
        // its own record, not end the walk.
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

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.count == 1)
        #expect(result.output.output.contains("extension Zerk<Logger>"))
        #expect(result.output.output.contains("nonisolated static func inject() -> Logger"))
    }
}
