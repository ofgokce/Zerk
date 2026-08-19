//
//  ParameterFidelityTests.swift
//  Zerk
//

import Testing
@testable import CodegenToolkit

/// What a generated member keeps of the parameter it stands for, over every
/// shape a parameter can take.
///
/// `ParameterRecord` modelled a parameter's *type* faithfully and its
/// parameter-ness not at all — no specifier, no ellipsis, no default — so three
/// facts were lost in three different ways and no two paths disagreed about any
/// of them. That is why comparing siblings, which found six earlier clusters,
/// found none of these: an omission leaves nothing to compare.
///
/// Each shape is asserted the same way — the generated file **compiles**, and
/// the member's signature says what the declaration said about anything Zerk did
/// not resolve. A golden string alone would not have caught the `inout` case at
/// all: the signature was right and the body, three lines below it, was not.
@Suite("Parameter fidelity")
struct ParameterFidelityTests {

    /// A parameter as written, and what the member must say about it.
    struct Shape {
        let name: String
        /// Declarations the fixture needs.
        let declarations: String
        /// The parameter, verbatim, as a provider would declare it.
        let parameter: String
        /// What the generated member's parameter list must contain, or `nil`
        /// when the shape is refused outright.
        let expected: String?

        static let all: [Shape] = [
            Shape(name: "plain", declarations: "", parameter: "n: Int", expected: "n: Int"),
            // The one specifier that changes a call site. The signature was
            // always right; the forwarding call omitted the `&`.
            Shape(name: "inout", declarations: "", parameter: "n: inout Int",
                  expected: "n: inout Int"),
            Shape(name: "borrowing", declarations: "public struct Payload { public init() {} }",
                  parameter: "p: borrowing Payload", expected: "p: borrowing Payload"),
            Shape(name: "consuming", declarations: "public struct Payload { public init() {} }",
                  parameter: "p: consuming Payload", expected: "p: consuming Payload"),
            Shape(name: "sending", declarations: "public struct Payload: Sendable { public init() {} }",
                  parameter: "p: sending Payload", expected: "p: sending Payload"),
            Shape(name: "escaping closure", declarations: "",
                  parameter: "f: @escaping () -> Void", expected: "f: @escaping () -> Void"),
            // Carried now; it used to vanish, making an optional argument
            // mandatory through Zerk while staying optional on the declaration.
            Shape(name: "defaulted", declarations: "", parameter: "n: Int = 5",
                  expected: "n: Int = 5"),
            Shape(name: "defaulted, implicit member",
                  declarations: "public enum Mode { case fast, slow }",
                  parameter: "m: Mode = .fast", expected: "m: Mode = .fast"),
            // Deliberately *not* carried: a magic literal captures where it was
            // written from, and the generated member is somewhere else. Found by
            // walking for the expression — a `#` in the rendered text is a
            // different question, and answered wrong in both directions.
            Shape(name: "defaulted with #function", declarations: "",
                  parameter: "caller: String = #function", expected: "caller: String"),
            Shape(name: "defaulted with a nested #function", declarations: "",
                  parameter: "who: String = String(describing: #function)",
                  expected: "who: String"),
            Shape(name: "defaulted with # inside a string", declarations: "",
                  parameter: #"tag: String = "issue #1""#,
                  expected: #"tag: String = "issue #1""#),
            Shape(name: "defaulted with a hex colour", declarations: "",
                  parameter: ##"hex: String = "#FF0000""##,
                  expected: ##"hex: String = "#FF0000""##),
            Shape(name: "defaulted with a raw string", declarations: "",
                  parameter: ###"raw: String = #"a\b"#"###,
                  expected: ###"raw: String = #"a\b"#"###),
            Shape(name: "no label", declarations: "", parameter: "_ n: Int", expected: "_ n: Int"),
            Shape(name: "two names", declarations: "", parameter: "with n: Int",
                  expected: "with n: Int"),
            // Refused: Swift cannot pass a variadic on, so no member Zerk could
            // emit would keep the declaration's contract.
            Shape(name: "variadic", declarations: "", parameter: "n: Int...", expected: nil),
        ]
    }

    @Test("a member keeps what the declaration said, and compiles",
          arguments: Shape.all)
    func providerParametersSurvive(shape: Shape) throws {
        let source = """
        \(shape.declarations)

        @Injectable
        public struct Consumer {
            @InjectableProviding
            public init(\(shape.parameter)) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        guard let expected = shape.expected else {
            #expect(result.diagnostics.contains { $0.severity == .error },
                    "\(shape.name) was accepted: \(result.diagnostics.map(\.message))")
            return
        }

        #expect(result.diagnostics.isEmpty, "\(shape.name): \(result.diagnostics.map(\.message))")
        #expect(result.output.output.contains("static func consumer(\(expected))"),
                "\(shape.name):\n\(result.output.output)")

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile,
                Comment(rawValue: "\(shape.name)\n\(compiled.compilerOutput)\n\(compiled.generated)"))
    }

    /// The same shapes on the other path: an unmarked parameter sitting beside
    /// an `@injected` one, forwarded into the generated overload.
    ///
    /// Both paths forward, so both had the `inout` defect. This one already
    /// carried defaults — `MarkedParameter` modelled them — which is what made
    /// it the control that showed the other model was incomplete.
    @Test("an @injected overload keeps what the declaration said, and compiles",
          arguments: Shape.all)
    func markedMemberParametersSurvive(shape: Shape) throws {
        let source = """
        \(shape.declarations)

        public protocol Serving {}

        @Injectable<Serving>
        public struct Live: Serving { public init() {} }

        public struct Screen {
            public init(@injected s: Serving, \(shape.parameter)) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        guard shape.expected != nil else {
            #expect(result.diagnostics.contains { $0.severity == .error },
                    "\(shape.name) was accepted: \(result.diagnostics.map(\.message))")
            return
        }

        #expect(result.diagnostics.isEmpty, "\(shape.name): \(result.diagnostics.map(\.message))")

        let compiled = try CompileFixture.run(source: source)
        try #require(!compiled.skipped)
        #expect(compiled.didCompile,
                Comment(rawValue: "\(shape.name)\n\(compiled.compilerOutput)\n\(compiled.generated)"))
    }
}

extension ParameterFidelityTests.Shape: CustomTestStringConvertible {
    var testDescription: String { name }
}
