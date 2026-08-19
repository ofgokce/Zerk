//
//  InjectedDeclarationSiteTests.swift
//  Zerk
//

import Testing
@testable import CodegenToolkit

/// Where an `@injected` member may be declared, against how generic the type
/// around it is.
///
/// A member declared in a type body knows its enclosing generic parameters; one
/// declared in an `extension` does not — an extension names no parameters of its
/// own, and the type it extends may be collected after it. So the extension path
/// hard-coded "not generic", and a marked parameter typed `Element` was matched
/// as an ordinary key: against a module type of the same name where one existed,
/// which emitted an extension the compiler rejected with both `Element`s spelled
/// identically in the error, and against nothing where one did not, which told
/// the developer to register a provider for a generic parameter.
///
/// The axis is the whole point. What is refused is not "an `@injected` member of
/// a generic type" — `@injected repo: Repo` in `extension Cache` resolves and is
/// supported, because the generated extension repeats the header and `E` stays
/// in scope for everything passed through. What cannot work is a *marked*
/// parameter naming one of those parameters, and only the pair says which is
/// which.
@Suite("@injected declaration sites")
struct InjectedDeclarationSiteTests {

    /// The enclosing type, and whether its parameters are in scope for a member
    /// written inside it.
    struct Enclosing {
        let name: String
        let declarations: String
        /// How the member is wrapped. `%@` is the member.
        let wrap: (String) -> String
        /// Whether a marked parameter typed `Element` names a generic parameter
        /// here.
        let elementIsGeneric: Bool

        static let all: [Enclosing] = [
            Enclosing(name: "non-generic type body",
                      declarations: "struct Screen {}",
                      wrap: { "extension Screen {\n\($0)\n}" },
                      elementIsGeneric: false),
            Enclosing(name: "generic extension, unbound",
                      declarations: "struct Cache<Element> {}",
                      wrap: { "extension Cache {\n\($0)\n}" },
                      elementIsGeneric: true),
            Enclosing(name: "generic extension, constrained",
                      declarations: "struct Cache<Element> {}",
                      wrap: { "extension Cache where Element: Equatable {\n\($0)\n}" },
                      elementIsGeneric: true),
            // Binding the arguments takes the parameters out of scope, so
            // `Element` here is whatever the module says it is.
            Enclosing(name: "generic extension, bound",
                      declarations: "struct Cache<E> {}",
                      wrap: { "extension Cache<Int> {\n\($0)\n}" },
                      elementIsGeneric: false),
            Enclosing(name: "global function",
                      declarations: "",
                      wrap: { $0 },
                      elementIsGeneric: false),
        ]
    }

    /// A concrete key resolves wherever it is written, however generic the type
    /// around it. This is the half that must keep working.
    @Test("a concrete key resolves at every declaration site",
          arguments: Enclosing.all)
    func concreteKeysResolveEverywhere(enclosing: Enclosing) {
        let result = CompileFixture.generateWithResolution(source: """
        protocol Repo {}

        @Injectable<Repo>
        struct RepoImpl: Repo {}

        struct Element {}

        \(enclosing.declarations)

        \(enclosing.wrap("func run(@injected repo: Repo, id: Int) -> Int { id }"))
        """)

        #expect(result.diagnostics.isEmpty,
                "\(enclosing.name): \(result.diagnostics.map(\.message))")
    }

    /// And a marked parameter naming one of the type's own generic parameters is
    /// refused exactly where it is one — with a module type of the same name in
    /// scope, so the silent misresolution is what the test is standing on.
    @Test("a marked parameter naming a generic parameter is refused where it is one",
          arguments: Enclosing.all)
    func genericParametersAreRefusedWhereTheyAreGeneric(enclosing: Enclosing) {
        let result = CompileFixture.generateWithResolution(source: """
        struct Element {}

        @Injectable<Element>
        func makeElement() -> Element { Element() }

        \(enclosing.declarations)

        \(enclosing.wrap("func run(@injected v: Element) {}"))
        """)

        let refusals = result.diagnostics.filter {
            $0.severity == .error && $0.message.contains("names a generic parameter")
        }
        #expect(refusals.isEmpty != enclosing.elementIsGeneric,
                "\(enclosing.name): \(result.diagnostics.map(\.message))")

        // Where it is not generic, the module type resolves and a member is
        // emitted — the control that keeps the refusal from spreading.
        if !enclosing.elementIsGeneric {
            #expect(result.diagnostics.isEmpty,
                    "\(enclosing.name): \(result.diagnostics.map(\.message))")
        }
    }

    /// A generic parameter mentioned *inside* another type is the same mistake,
    /// and used to produce the same misleading "not injectable" advice.
    @Test("a marked parameter mentioning a generic parameter is refused too")
    func mentionedGenericParametersAreRefused() {
        let result = CompileFixture.generateWithResolution(source: """
        struct Box<E> {}
        struct Cache<Element> {}

        extension Cache {
            func run(@injected b: Box<Element>) {}
        }
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .error && $0.message.contains("names a generic parameter of 'Cache'")
        }, "\(result.diagnostics.map(\.message))")
    }
}

extension InjectedDeclarationSiteTests.Enclosing: CustomTestStringConvertible {
    var testDescription: String { name }
}
