//
//  InitializerInferenceTests.swift
//  Zerk
//

import Testing
import SwiftParser
@testable import CodegenToolkit

/// What Zerk assumes about an initializer it never sees written.
///
/// The plugin reads syntax and does not expand macros, so a property carrying
/// one looks like a plain stored property — which is how `@Injected` and
/// `@InjectedDynamically` used to be turned into memberwise parameters that the
/// expanded type does not have, producing `argument passed to call that takes no
/// arguments` inside the generated file.
///
/// `CompileFixture` cannot verify this family: it strips Zerk attributes before
/// handing the source to `swiftc`, which is exactly the information under test.
/// The emitted shapes here were checked against the real macro plugin by
/// building a package that uses them.
@Suite("Initializer inference")
struct InitializerInferenceTests {

    private static func types(_ source: String) -> [TypeRecord] {
        let collector = SourceCollector()
        collector.walk(Parser.parse(source: source))
        return collector.types
    }

    // MARK: - Zerk's own property macros

    @Test("a struct's @Injected property is not a memberwise parameter",
          arguments: ["@Injected", "@InjectedDynamically"])
    func structPropertyMacrosAreNotParameters(attribute: String) throws {
        let types = Self.types("""
        @Injectable
        struct Screen {
            \(attribute) var service: Service
        }
        """)

        // The macro gives the property its value — a peer with a default for
        // `@Injected`, a getter for `@InjectedDynamically` — so the expanded
        // type's initializer takes nothing.
        let initializer = try #require(types.first?.initializers.first)
        #expect(types.count == 1)
        #expect(initializer.parameters.isEmpty)
    }

    @Test("a class whose only properties are injected gets init() inferred",
          arguments: ["@Injected", "@InjectedDynamically"])
    func classPropertyMacrosAllowDefaultInit(attribute: String) throws {
        let types = Self.types("""
        @Injectable
        final class Screen {
            \(attribute) var service: Service
        }
        """)

        // Before this, the property looked uninitialized, so no `init()` was
        // inferred and the type was reported as having no provider at all.
        let initializer = try #require(types.first?.initializers.first)
        #expect(types.count == 1)
        #expect(initializer.parameters.isEmpty)
    }

    // MARK: - What must not change

    @Test("a plain struct still gets its memberwise parameters")
    func plainStructIsUnchanged() {
        let types = Self.types("""
        @Injectable
        struct Screen {
            let service: Service
            let logger: Logger
        }
        """)

        #expect(types.first?.initializers.first?.parameters.map(\.name) == ["service", "logger"])
    }

    /// Swift synthesizes nothing for this, so neither may Zerk. Class inference
    /// must stay exactly as wide as the compiler's, not wider.
    @Test("a class with an uninitialized stored property infers nothing")
    func classWithRequiredPropertyInfersNothing() {
        let types = Self.types("""
        @Injectable
        final class Screen {
            let service: Service
        }
        """)

        #expect(types.first?.initializers.isEmpty == true)
    }

    @Test("a defaulted property is not a parameter, whatever it carries")
    func defaultedPropertiesAreSkipped() {
        let types = Self.types("""
        @Injectable
        struct Screen {
            @Whatever var mode: Int = 0
            let service: Service
        }
        """)

        // The guard below is about *required* parameters only: a property that
        // already has a value is not asked for either way.
        #expect(types.first?.initializers.first?.parameters.map(\.name) == ["service"])
    }

    // MARK: - The guard

    @Test("an attribute Zerk cannot read stops the inference")
    func unreadableAttributeRefusesInference() {
        let types = Self.types("""
        @Injectable
        struct Screen {
            @Clamped var mode: Int
            let service: Service
        }
        """)

        #expect(types.first?.initializers.isEmpty == true)
        let refusal = types.first?.initializerInferenceRefusal
        #expect(refusal?.contains("'@Clamped' on 'mode'") == true, "\(refusal ?? "nil")")
    }

    /// The refusal is only a problem if nothing else builds the type, so it
    /// rides on the existing "no provider" error rather than firing its own.
    @Test("the refusal is explained by the error that would fire anyway")
    func refusalReachesTheDiagnostic() {
        let result = CompileFixture.generateWithResolution(source: """
        @Injectable
        struct Screen {
            @Clamped var mode: Int
            let service: Service
        }
        """)

        let errors = result.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1)
        #expect(errors.first?.message.contains("No @InjectableProviding provider found") == true)
        #expect(errors.first?.message.contains("'@Clamped' on 'mode'") == true)
    }

    @Test("declaring a provider makes the refusal moot")
    func explicitProviderSatisfiesTheRefusal() {
        let result = CompileFixture.generateWithResolution(source: """
        @Injectable
        struct Screen {
            @Clamped var mode: Int
            let service: Service

            @InjectableProviding
            static func make() -> Screen { fatalError() }
        }
        """)

        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
    }

    /// Verified against the compiler: a global actor on a stored property
    /// changes neither the synthesized initializer's parameters nor its
    /// isolation — a nonisolated initializer may still initialize an isolated
    /// stored property.
    @Test("a global actor on a property does not stop the inference",
          arguments: ["@MainActor", "@StoreActor"])
    func globalActorsAreReadable(actor: String) {
        let types = Self.types("""
        @Injectable
        struct Screen {
            \(actor) var mode: Int
            let service: Service
        }
        """)

        #expect(types.first?.initializers.first?.parameters.map(\.name) == ["mode", "service"])
    }

    @Test("a wrapper whose memberwise value is the wrapped one is read as such")
    func wrappedValueWrappersAreReadable() {
        let types = Self.types("""
        @Injectable
        struct Screen {
            @Bindable var model: SearchModel
        }
        """)

        // `@Bindable` has `init(wrappedValue:)`, so the memberwise initializer
        // takes a `SearchModel` — which is what reading the annotation gives.
        #expect(types.first?.initializers.first?.parameters.map(\.typeKey) == ["SearchModel"])
    }
}

/// Cycles that run through an `@Injected` property rather than an initializer
/// parameter.
///
/// These were invisible: a property is not a provider parameter, so it left no
/// edge in the graph, and the build succeeded and then overflowed the stack on
/// the first resolution — `@Injected` resolves while the instance is being
/// built.
@Suite("Property cycles")
struct PropertyCycleTests {

    private static func diagnostics(_ source: String) -> [CodegenDiagnostic] {
        CompileFixture.generateWithResolution(source: source).diagnostics
    }

    @Test("an @Injected cycle between classes is caught", arguments: ["final class", "struct"])
    func eagerPropertyCycleIsCaught(kind: String) {
        let diagnostics = Self.diagnostics("""
        @Injectable \(kind) A { @Injected var b: B }
        @Injectable \(kind) B { @Injected var a: A }
        """)

        #expect(diagnostics.contains {
            $0.severity == .error && $0.message.contains("Circular dependency detected")
        }, "\(diagnostics.map(\.message))")
    }

    @Test("the error names the lazy remedy")
    func cycleErrorNamesTheRemedy() {
        let message = Self.diagnostics("""
        @Injectable final class A { @Injected var b: B }
        @Injectable final class B { @Injected var a: A }
        """).first { $0.message.contains("Circular dependency") }?.message

        #expect(message?.contains("@InjectedDynamically resolves on each access") == true,
                "\(message ?? "nil")")
    }

    /// The remedy has to actually work, or the message is a lie.
    @Test("an @InjectedDynamically cycle is accepted")
    func lazyPropertyCycleIsAccepted() {
        let diagnostics = Self.diagnostics("""
        @Injectable final class A { @InjectedDynamically var b: B }
        @Injectable final class B { @InjectedDynamically var a: A }
        """)

        #expect(diagnostics.isEmpty, "\(diagnostics.map(\.message))")
    }

    @Test("a plain initializer cycle keeps its own wording")
    func constructorCycleIsUnchanged() {
        let message = Self.diagnostics("""
        @Injectable struct A { let b: B }
        @Injectable struct B { let a: A }
        """).first { $0.message.contains("Circular dependency") }?.message

        #expect(message != nil)
        #expect(message?.contains("@InjectedDynamically") == false, "\(message ?? "nil")")
    }

    /// An `@Injected` property in something Zerk does not build is not a node in
    /// this graph, so it cannot close a cycle in it.
    @Test("an @Injected property outside an injectable type is not an edge")
    func usesOutsideInjectablesAreNotEdges() {
        let diagnostics = Self.diagnostics("""
        @Injectable struct Service { let helper: Helper }
        @Injectable struct Helper {}

        final class Screen {
            @Injected var service: Service
        }
        """)

        #expect(diagnostics.isEmpty, "\(diagnostics.map(\.message))")
    }
}
