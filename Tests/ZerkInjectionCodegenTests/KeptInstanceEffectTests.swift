//
//  KeptInstanceEffectTests.swift
//  Zerk
//

import Testing
@testable import CodegenToolkit

/// What a consumer pays to read a kept instance, over the whole cross product of
/// construction effects and consumer shapes.
///
/// Reading a kept instance is not what building one cost — the box turns a
/// throwing construction into an `async throws` read — and three places write a
/// call to it: the member that resolves a dependency into its body, `inject()`,
/// and the generated `@injected` overload. Two of them asked the shared rule and
/// one recomputed it, which nothing noticed while *async* constructions were the
/// only ones covered: there the two answers agree. Throwing-only construction
/// was enough to emit `static func consumer() throws` whose body called an
/// `async` `inject()`, with no diagnostic and a generated file that did not
/// compile.
///
/// So this is written as a cross product rather than one test per shape: what
/// was missing was a *combination*, not a spelling, and a suite pinned to the
/// reported input would have left the next combination open in the same way.
@Suite("Kept instance effects")
struct KeptInstanceEffectTests {

    /// A construction effect, and what reading the instance costs afterwards.
    struct Construction {
        let name: String
        /// The effect clause written on the initializer.
        let built: String
        /// The clause every consumer must carry. `throws` alone widens to
        /// `async throws`, because joining the one build is what suspends; no
        /// effects at all keeps the cheap synchronous storage and reads free.
        let read: String

        static let all: [Construction] = [
            Construction(name: "none", built: "", read: ""),
            Construction(name: "throws", built: "throws", read: " async throws"),
            Construction(name: "async", built: "async", read: " async"),
            Construction(name: "async throws", built: "async throws", read: " async throws"),
        ]
    }

    /// The two ways an instance is kept. Once the construction has effects both
    /// read through ``ZerkAsyncBox``, so the rule cannot differ between them —
    /// and the divergence this suite covers was in code that never asked which
    /// one it was looking at.
    struct Sharing {
        let name: String
        let attribute: String
        /// What the fixture needs declared for the attribute to resolve.
        let declarations: String

        static let all: [Sharing] = [
            Sharing(name: "singleton", attribute: "@Singleton", declarations: ""),
            Sharing(name: "scoped", attribute: "@Scoped(.session)", declarations: """
            extension InjectionScope {
                nonisolated static let session = InjectionScope("session")
            }
            """),
        ]
    }

    @Test("every consumer of a kept instance reads it with the box's effects",
          arguments: Construction.all, Sharing.all)
    func consumersAgreeOnTheReadEffects(construction: Construction,
                                        sharing: Sharing) throws {
        let source = """
        \(sharing.declarations)

        protocol Connecting: Sendable {}

        \(sharing.attribute)
        @Injectable<Connecting>
        final class Client: Connecting, @unchecked Sendable {
            init() \(construction.built) {}
        }

        // Resolved into a member's body, and again through `inject()`.
        @Injectable
        struct Consumer {
            let connecting: Connecting
        }

        // Resolved into a generated overload, which is the third emitter.
        struct Screen {
            func show(@injected connecting: Connecting, title: String) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)
        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")

        let generated = result.output.output
        #expect(generated.contains(
            "nonisolated static func inject()\(construction.read) -> Consumer {"),
                "inject():\n\(generated)")
        #expect(generated.contains(
            "nonisolated func show(title: String)\(construction.read) {"),
                "@injected overload:\n\(generated)")

        // The compiler is the oracle that matters. The defect is a *body*
        // calling something the member's own signature cannot support, which no
        // golden string of a signature can see — both halves look right on their
        // own, and only the pair is wrong.
        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile,
                Comment(rawValue: "\(compiled.compilerOutput)\n\(compiled.generated)"))
    }
}

extension KeptInstanceEffectTests.Construction: CustomTestStringConvertible {
    var testDescription: String { name }
}

extension KeptInstanceEffectTests.Sharing: CustomTestStringConvertible {
    var testDescription: String { name }
}
