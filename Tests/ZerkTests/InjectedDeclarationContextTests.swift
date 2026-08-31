//
//  InjectedDeclarationContextTests.swift
//  Zerk
//

import Testing
import MacroToolkit
import SwiftDiagnostics
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros

/// Which declaration contexts `@Injected` can expand in, as one list.
///
/// `@Injected` adds a peer that initializes the property through
/// `@storageRestrictions(initializes:)`, which hooks the moment an *instance*
/// initializes its stored properties. A `static` or file-scope property has no
/// such moment: the peer never runs, the declaration is left with no
/// initializer, and the compiler reports "requires an initializer expression or
/// an explicitly stated getter" — a message naming neither Zerk nor the fix, on
/// a declaration that looks exactly like the supported one.
///
/// `InjectedPropertyInfo` validated seven declaration *shapes* and no
/// declaration *context*, which is the same gap twice over: a rule applied on
/// one path and not on its sibling. So the contexts are a list here rather than
/// a test apiece, and the accepted ones are in it too — the guard must refuse
/// the two without narrowing what has always worked.
@Suite("@Injected declaration contexts")
struct InjectedDeclarationContextTests {

    struct Context {
        let name: String
        /// The declaration, `@Injected` and all.
        let declaration: String
        /// What encloses it. Empty means file scope.
        let enclosing: String?
        let isAccepted: Bool

        static let all: [Context] = [
            Context(name: "instance property of a struct",
                    declaration: "@Injected var repository: Repository",
                    enclosing: "struct Screen {}",
                    isAccepted: true),
            Context(name: "instance property of a class",
                    declaration: "@Injected var repository: Repository",
                    enclosing: "final class Screen {}",
                    isAccepted: true),
            Context(name: "instance property of a nested type",
                    declaration: "@Injected var repository: Repository",
                    enclosing: "struct Inner {}",
                    isAccepted: true),
            Context(name: "static property",
                    declaration: "@Injected static var repository: Repository",
                    enclosing: "enum Holder {}",
                    isAccepted: false),
            // `class var` is the same declaration under another spelling, and
            // `DeclModifierSyntax.isStatic` counts it as one.
            Context(name: "class property",
                    declaration: "@Injected class var repository: Repository",
                    enclosing: "class Holder {}",
                    isAccepted: false),
            Context(name: "file scope",
                    declaration: "@Injected var repository: Repository",
                    enclosing: nil,
                    isAccepted: false),
        ]
    }

    @Test("@Injected expands for an instance property and refuses the rest",
          arguments: Context.all)
    func injectedRefusesContextsWithNoInitialization(context: Context) throws {
        let (info, diagnostics) = try expand(context)

        if context.isAccepted {
            #expect(info != nil, "\(context.name): \(diagnostics.map(\.message))")
            #expect(diagnostics.isEmpty, "\(context.name): \(diagnostics.map(\.message))")
        } else {
            #expect(info == nil, "\(context.name) was accepted")
            // Named, and with the alternative in it: the whole point is that the
            // compiler's own message says nothing about Zerk.
            #expect(diagnostics.contains {
                $0.message.contains("@Injected") && $0.message.contains("@InjectedDynamically")
            }, "\(context.name): \(diagnostics.map(\.message))")
        }
    }

    /// `@InjectedDynamically` generates a getter rather than initializing
    /// storage, so it is at home in every context above — including the two the
    /// guard refuses. Asserted so the refusal cannot quietly spread to it.
    @Test("@InjectedDynamically expands in every context", arguments: Context.all)
    func injectedDynamicallyAcceptsEveryContext(context: Context) throws {
        let source = context.declaration.replacingOccurrences(
            of: "@Injected ", with: "@InjectedDynamically ")
        let (info, diagnostics) = try expand(
            Context(name: context.name,
                    declaration: source,
                    enclosing: context.enclosing,
                    isAccepted: true),
            macroName: "@InjectedDynamically",
            requiresInstanceStorage: false)

        // The `class var` row is the one exception, and not for its context: a
        // getter needs a `var`, and `class var` is one — but `requiresVar` is
        // what this asserts nothing about.
        #expect(info != nil, "\(context.name): \(diagnostics.map(\.message))")
    }

    // MARK: - Harness

    // MARK: - @Observable

    /// `@Observable` rewrites a stored property into a computed one, which
    /// `@Injected` cannot initialize. Refused on the developer's own
    /// declaration, before an init accessor naming a computed property is
    /// generated and the compiler reports that against code nobody wrote.
    @Test("an observed property is refused where it was written")
    func anObservedPropertyIsRefused() throws {
        let (info, diagnostics) = try expand(
            Context(name: "@Observable class",
                    declaration: "@Injected var serving: Serving",
                    enclosing: "@Observable final class Model {}",
                    isAccepted: false))

        #expect(info == nil)
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.message.contains("cannot resolve an observed property") == true)
        #expect(diagnostics.first?.message.contains("@ObservationIgnored") == true)
    }

    /// The supported spelling, which must not trip the refusal above — the
    /// attribute identifying `@Observable`'s own copy of this macro is the same
    /// one the developer writes to opt out.
    @Test("an @ObservationIgnored property is accepted")
    func anObservationIgnoredPropertyIsAccepted() throws {
        let (info, diagnostics) = try expand(
            Context(name: "@Observable class, ignored",
                    declaration: "@ObservationIgnored @Injected var serving: Serving",
                    enclosing: "@Observable final class Model {}",
                    isAccepted: true))

        #expect(diagnostics.isEmpty)
        #expect(info != nil)
    }

    /// `@ObservationTracked` copies this macro onto the backing storage it
    /// generates, which expands with no lexical context. Read as file scope,
    /// that produced "a global has no such moment" for a class property, naming
    /// storage the developer never wrote.
    @Test("@Observable's copy is not mistaken for a global")
    func theObservableCopyIsNotAGlobal() throws {
        let (info, diagnostics) = try expand(
            Context(name: "generated backing storage",
                    declaration: "@Injected @ObservationIgnored private var _serving: Serving",
                    enclosing: nil,
                    isAccepted: false))

        #expect(info == nil)
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.message.contains("cannot resolve an observed property") == true)
        #expect(diagnostics.first?.message.contains("a global has no such moment") == false)
    }

    private func expand(_ context: Context,
                        macroName: String = "@Injected",
                        requiresInstanceStorage: Bool = true) throws
    -> (InjectedPropertyInfo?, [Diagnostic]) {
        let file = Parser.parse(source: context.declaration)
        let variable = try #require(
            file.statements.first?.item.as(VariableDeclSyntax.self))
        guard case .attribute(let attribute)? = variable.attributes.first else {
            Issue.record("no attribute parsed from \(context.declaration)")
            return (nil, [])
        }

        // The macro reads its context through `lexicalContext`, which is empty
        // exactly when nothing encloses the declaration. Built from a parsed
        // declaration rather than a hand-assembled node so it is the shape the
        // compiler passes.
        var lexicalContext: [Syntax] = []
        if let enclosing = context.enclosing {
            let parsed = Parser.parse(source: enclosing)
            lexicalContext = [Syntax(try #require(parsed.statements.first?.item))]
        }

        let expansionContext = BasicMacroExpansionContext(lexicalContext: lexicalContext)
        let info = InjectedPropertyInfo(
            from: variable,
            attribute: attribute,
            macroName: macroName,
            allowObservers: requiresInstanceStorage,
            allowLazyModifier: false,
            requiresVar: !requiresInstanceStorage,
            requiresInstanceStorage: requiresInstanceStorage,
            context: expansionContext)

        return (info, expansionContext.diagnostics)
    }
}

extension InjectedDeclarationContextTests.Context: CustomTestStringConvertible {
    var testDescription: String { name }
}
