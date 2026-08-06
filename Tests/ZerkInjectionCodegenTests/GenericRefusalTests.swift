//
//  GenericRefusalTests.swift
//  Zerk
//

import Testing
import SwiftParser
@testable import CodegenToolkit
import SharedToolkit

/// Coverage of the generic registrations Zerk still refuses, and why each one is
/// refused rather than emitted.
///
/// Generic types themselves now go through — see `GenericEmissionTests`. What is
/// left here has no legal form at all, so refusing is the whole answer:
///
/// - `@Singleton`, permanently, because a static stored property is illegal in a
///   generic type;
/// - a written `@Injectable<K>` key, because the attribute cannot name the
///   type's parameters;
/// - a generic provider or value *function*, whose return type names parameters
///   the key does not bind.
///
/// Every message is also raised by the matching macro, from ``GenericRefusal``,
/// so the two surfaces cannot drift.
@Suite("Generic refusals")
struct GenericRefusalTests {

    // MARK: - Types

    @Test("@Singleton on a generic type is refused")
    func genericSingletonIsRefused() {
        // A singleton's storage is a static stored property, and Swift does not
        // allow one in a generic type — there is nowhere to keep an instance per
        // specialization. This does not lift.
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
        #expect(!result.output.output.contains("Registry"))
    }

    @Test("a parameter no argument can infer is refused")
    func unboundParameterIsRefused() {
        // A written key erases the type's parameters, so the member has to
        // recover each one from its arguments. `E` appears nowhere in this
        // initializer, so nothing at the call site could ever infer it — Swift
        // says "generic parameter 'E' is not used in function signature"; this
        // says it at the declaration.
        let source = """
        protocol Caching {}

        @Injectable<any Caching>
        struct Cache<E>: Caching {
            @InjectableProviding
            init() {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.contains {
            $0.severity == .error
                // Echoed as written: keys match with `any` stripped, but a
                // developer told about `Caching` when they wrote `any Caching`
                // has to work out that those are the same thing.
                && $0.message.contains("@Injectable<any Caching> erases 'E' from 'Cache'")
                && $0.message.contains("Accept 'E' as a parameter")
        })
        #expect(!result.output.output.contains("extension Zerk<any Caching>"))
    }

    @Test("only the uninferable parameters are named")
    func onlyUnboundParametersAreNamed() {
        let source = """
        protocol Boxing {}

        @Injectable<any Boxing>
        struct Box<X, Y>: Boxing {
            @InjectableProviding
            init(_ x: X) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        // `X` arrives as an argument; only `Y` is unreachable.
        #expect(result.diagnostics.contains {
            $0.message.contains("erases 'Y' from 'Box'") && !$0.message.contains("'X'")
        })
    }

    @Test("parameterized: on a non-generic type is refused")
    func parameterizedNonGenericIsRefused() {
        let source = """
        protocol Boxable<X> { associatedtype X }

        @Injectable<any Boxable>(parameterized: true)
        struct Plain: Boxable {
            typealias X = Int
            @InjectableProviding
            init() {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.contains {
            $0.message.contains("applies 'Plain's own generic parameters to the key, and 'Plain' has none")
        })
    }

    @Test("parameterized: needs an existential key")
    func parameterizedNeedsAny() {
        // Zerk never *adds* `any`: it reads tokens, so it cannot tell a protocol
        // from a class, and `any` on a class is a compile error.
        let source = """
        protocol Boxable<X> { associatedtype X }

        @Injectable<Boxable>(parameterized: true)
        struct Box<X>: Boxable {
            @InjectableProviding
            init(_ x: X) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.contains {
            $0.message.contains("needs an existential key. Write 'any Boxable'")
        })
        // Exactly one error: a failed `parameterized:` must not also be reported
        // against the plain key path.
        #expect(result.diagnostics.count == 1)
    }

    @Test("parameterized: needs the arities to match")
    func parameterizedArityMustMatch() {
        let source = """
        protocol Boxable<X> { associatedtype X; associatedtype Y }

        @Injectable<any Boxable>(parameterized: true)
        struct Box<X, Y>: Boxable {
            @InjectableProviding
            init(_ x: X, _ y: Y) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.contains {
            $0.message.contains("applies 2 parameters of 'Box'")
                && $0.message.contains("protocol declaring 1 primary associated type")
        })
        #expect(result.diagnostics.count == 1)
    }

    // MARK: - Members

    @Test("a provider parameter its own arguments cannot infer is refused",
          arguments: [
            ("the initializer", """
             @Injectable
             struct Box {
                 @InjectableProviding
                 init<Z>(label: String) {}
             }
             """),
            ("'live'", """
             @Injectable
             struct Box {
                 @InjectableProviding
                 static func live<Z>(label: String) -> Box { .init() }
                 init() {}
             }
             """),
          ])
    func unboundProviderParameterIsRefused(_ member: String, _ source: String) {
        // A parameter the provider declares itself can only come from its own
        // arguments — no key describes it, whatever the key is. So this is
        // refused even on a non-generic type.
        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.contains {
            $0.severity == .error
                && $0.message.contains("'Box': \(member) declares 'Z'")
                && $0.message.contains("does not appear in its parameters")
        })
    }

    @Test("a generic injectable value function is refused for being a function")
    func genericInjectableValueFunctionIsRefused() {
        let source = """
        struct Box<E> {}

        enum Values {
            @InjectableValue
            static func boxed<E>() -> Box<E> { .init() }
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        // Genericity never comes into it any more: `@InjectableValue` does not
        // apply to a function at all, so that is the reason reported.
        #expect(result.diagnostics.contains {
            $0.severity == .error
                && $0.message == InjectableValueRefusal.functionTarget
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

    // MARK: - The seam

    @Test("the gate is the only thing that refuses a generic type")
    func theGateIsTheOnlyRefusal() throws {
        // Reading and refusing are separate. The collector records every generic
        // type in full and says nothing; `GenericGate` decides which of them
        // have a legal form. This pins that shape, so the remaining refusals
        // stay in one place.
        let source = """
        @Singleton
        @Injectable
        final class Registry<E> {
            @InjectableProviding
            init() {}
        }

        @Injectable
        struct Cache<E> {
            @InjectableProviding
            init(serializer: Serializer<E>) {}
        }
        """

        let collector = SourceCollector()
        collector.walk(Parser.parse(source: source))

        #expect(collector.diagnostics.isEmpty)
        #expect(collector.types.count == 2)

        let gate = GenericGate.admitted(collector.types)
        // The singleton is refused; the plain generic type is admitted.
        #expect(gate.diagnostics.count == 1)
        #expect(gate.diagnostics[0].message.contains("'Registry'"))
        #expect(gate.types.map(\.name) == ["Cache"])
    }

    // MARK: - Blast radius

    @Test("refusing one type leaves the rest of the module generated")
    func refusingOneTypeLeavesTheRestGenerated() {
        // The gate drops the refused type's record. That must drop only its own,
        // and must not stop the resolver from serving everything else.
        let source = """
        @Singleton
        @Injectable
        final class Registry<E> {
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
