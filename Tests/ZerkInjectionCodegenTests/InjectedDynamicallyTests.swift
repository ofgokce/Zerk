//
//  InjectedDynamicallyTests.swift
//  Zerk
//

import Testing
@testable import CodegenToolkit

/// What the plugin has to emit for `@InjectedDynamically` to work in a target that
/// runs it.
///
/// The stakes here are the shadowing rule: a module-local declaration of a macro
/// name hides *every* overload of that name in `Zerk`, so a form the generated
/// file forgets does not fall back — it stops existing. These tests are the
/// guard against forgetting one.
@Suite("@InjectedDynamically")
struct InjectedDynamicallyTests {

    private static let source = """
    protocol Serving {}

    @Injectable<Serving>
    struct Live: Serving {
        @InjectableProviding
        init() {}
    }

    @Injectable
    struct Seeded {
        @InjectableProviding
        init(seed: Int) {}
    }
    """

    @Test("every @InjectedDynamically form is re-declared")
    func redeclaresEveryForm() {
        let output = CompileFixture.generate(source: Self.source)

        #expect(output.contains(
            "macro InjectedDynamically() = #externalMacro(module: \"ZerkMacros\", type: \"InjectedDynamicallyMacro\")"))
        #expect(output.contains(
            "macro InjectedDynamically<T>() = #externalMacro(module: \"ZerkMacros\", type: \"InjectedDynamicallyMacro\")"))
        #expect(output.contains(
            "macro InjectedDynamically<T>(_ keyPath: KeyPath<Zerk<T>.Type, T>) = #externalMacro(module: \"ZerkMacros\", type: \"InjectedDynamicallyMacro\")"))

        // Accessor role, not peer — that distinction is the whole reason this is
        // a separate attribute rather than an argument on @Injected.
        let declaration = output.range(of: "macro InjectedDynamically()")
        let precedingAttribute = declaration.map { output[..<$0.lowerBound] }?.hasSuffix("@attached(accessor)\n")
        #expect(precedingAttribute == true)
    }

    @Test("an argument-forwarding signature gets a dynamic counterpart")
    func forwardsArgumentsDynamically() {
        let output = CompileFixture.generate(source: Self.source)

        #expect(output.contains("macro Injected(seed: Int) = #externalMacro"))
        #expect(output.contains("macro InjectedDynamically(seed: Int) = #externalMacro"))
    }

    @Test("each macro name keeps to one role: Injected peer, InjectedDynamically accessor")
    func rolesDoNotMix() {
        let lines = CompileFixture.generate(source: Self.source)
            .split(separator: "\n", omittingEmptySubsequences: false)

        // The rule this whole design turns on: overloads of one macro name must
        // agree on their roles. An accessor overload of `Injected` crashes
        // SILGen while lowering the *peer* variant — on properties that have
        // nothing to do with it — so a mixed emission here is a build that dies
        // somewhere unrelated and inexplicable.
        //
        // Matched on the exact name rather than a prefix. `InjectedDynamically`
        // begins with `Injected`, so a prefix test reads every dynamic
        // declaration as an `Injected` one and demands the wrong role of it.
        var roles: [String: Set<String>] = [:]
        for index in lines.indices.dropFirst() {
            let declaration = lines[index]
            guard declaration.hasPrefix("macro ") else {
                continue
            }
            let name = declaration
                .dropFirst("macro ".count)
                .prefix { $0 != "(" && $0 != "<" }
            roles[String(name), default: []].insert(String(lines[index - 1]))
        }

        #expect(roles["Injected"] == ["@attached(peer, names: prefixed(_$zerk_injection_))"])
        #expect(roles["InjectedDynamically"] == ["@attached(accessor)"])
        // Nothing else should be declaring macros in there.
        #expect(Set(roles.keys) == ["Injected", "InjectedDynamically"])
    }

    @Test("a dynamic property gets the same chain check, named after its own attribute")
    func reportsAnEffectfulChain() {
        let source = """
        protocol Serving {}

        @Injectable<Serving>
        struct Live: Serving {
            @InjectableProviding
            static func make() async -> Serving { Live() }
        }

        struct Consumer {
            @InjectedDynamically var service: Serving
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)
        let errors = result.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1)
        // A getter cannot `await` any more than an initializer can, so the check
        // is the same one — but the message quotes what was written.
        #expect(errors.first?.message.contains("@InjectedDynamically cannot resolve it") == true)
    }
}
