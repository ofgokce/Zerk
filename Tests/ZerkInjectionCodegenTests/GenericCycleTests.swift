//
//  GenericCycleTests.swift
//  Zerk
//

import Testing
@testable import CodegenToolkit

/// Coverage of recursion and cycle detection where the key is a *shape*.
///
/// A generic registration is filed under `Cache<#0>`, while a parameter naming
/// one of its specializations carries `Cache<String>`. Anything that compares a
/// parameter's key against the set of registration keys therefore never matches
/// — while `KeyIndex` resolves one to the other quite happily. That combination
/// recursed until the stack ran out: `ParameterClassifier` descended forever,
/// and `cycleDiagnostics` built an edge to a node that did not exist, so nothing
/// reported it either.
///
/// Both now resolve the parameter first and work from the *dependency's* key.
@Suite("Generic cycles")
struct GenericCycleTests {

    @Test("a self-referential generic type is reported, not recursed into")
    func genericSelfReferenceIsReported() {
        // Before the fix this crashed the codegen with SIGSEGV.
        let result = CompileFixture.generateWithResolution(source: """
        @Injectable
        struct Node<E> {
            @InjectableProviding
            init(child: Node<Int>) {}
        }
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error && $0.message.contains("Circular dependency detected")
        })
    }

    @Test("a generic cycle names the key as the developer spelled it")
    func genericCycleUsesTheWrittenSpelling() {
        // `Cache<#0>` is Zerk's own shape notation and appears nowhere in the
        // developer's source, so the diagnostic must not use it.
        let result = CompileFixture.generateWithResolution(source: """
        @Injectable
        struct Cache<E> {
            @InjectableProviding
            init(other: Cache<String>) {}
        }
        """)

        #expect(result.diagnostics.contains {
            $0.message.contains("Cache<E> -> Cache<E>")
        })
        #expect(!result.diagnostics.contains { $0.message.contains("#0") })
    }

    @Test("a two-step generic cycle is reported")
    func genericIndirectCycleIsReported() {
        let result = CompileFixture.generateWithResolution(source: """
        @Injectable
        struct Left<E> {
            @InjectableProviding
            init(right: Right<Int>) {}
        }

        @Injectable
        struct Right<E> {
            @InjectableProviding
            init(left: Left<Int>) {}
        }
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error && $0.message.contains("Circular dependency detected")
        })
    }

    @Test("a non-generic cycle still reports exactly as before", arguments: [
        ("""
        @Injectable
        struct Node {
            @InjectableProviding
            init(child: Node) {}
        }
        """, "Node -> Node"),
        ("""
        @Injectable
        struct A { @InjectableProviding init(b: B) {} }

        @Injectable
        struct B { @InjectableProviding init(a: A) {} }
        """, "A -> B -> A"),
    ])
    func nonGenericCyclesUnchanged(source: String, path: String) {
        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.contains { $0.message.contains(path) })
    }

    @Test("a generic dependency that is not a cycle still resolves")
    func genericNonCycleStillResolves() throws {
        // The guard must not fire on a legitimate generic dependency — the
        // failure mode of over-correcting is that everything becomes external.
        let source = """
        @Injectable
        struct Codec<E> {
            @InjectableProviding
            init() {}
        }

        @Injectable
        struct Repository<E> {
            @InjectableProviding
            init(codec: Codec<E>) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        // Resolved as a defaulted argument, not pushed onto the caller.
        #expect(result.output.output.contains("codec: Codec<E> = Zerk<Codec<E>>.inject()"))

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile, "\(compiled.compilerOutput)")
    }
}
