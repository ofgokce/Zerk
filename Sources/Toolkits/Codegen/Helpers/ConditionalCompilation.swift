//
//  ConditionalCompilation.swift
//  Zerk
//

import SwiftSyntax

/// What Zerk needs to know about a `#if` block without evaluating it.
///
/// Zerk carries conditions rather than resolving them — see
/// ``CompilationCondition`` for why it cannot resolve them — and carrying works
/// by wrapping the generated code in the same guard. That is possible whenever
/// the `#if` encloses *whole declarations*: the code Zerk generates for a
/// declaration is its own, so it can be wrapped on its own.
///
/// It stops being possible when the `#if` is inside a type Zerk registers and
/// gates part of how that type is *built*. A conditional initializer would give
/// one type two provider shapes, only one of which exists in any build, and the
/// generated member has a single signature. This finds that case so it can be
/// refused rather than silently miscompiled.
enum ConditionalCompilation {

    /// Whether a `#if` inside a type body gates something that decides how the
    /// type is constructed.
    ///
    /// Only initializers and `@InjectableProviding` qualify. An `@InjectableValue`
    /// inside a type body is not a provider *of that type* — it is its own
    /// registration, with its own generated member, and so it is wrapped like any
    /// other declaration. Anything with no Zerk meaning at all — a conditional
    /// method, a conditional stored property, a `#if` around an import — is none
    /// of Zerk's business, and passes through untouched.
    static func gatesConstruction(_ node: IfConfigDeclSyntax) -> Bool {
        Finder.found(in: Syntax(node))
    }

    /// Attributes that make a member a provider of its enclosing type.
    ///
    /// The parameter markers are deliberately absent: they qualify a parameter of
    /// a declaration that is itself inside the block, so the declaration has
    /// already matched on its own.
    private static let constructionAttributes: Set<String> = ["InjectableProviding"]

    private final class Finder: SyntaxVisitor {
        private var didFind = false

        static func found(in node: Syntax) -> Bool {
            let finder = Finder(viewMode: .sourceAccurate)
            finder.walk(node)
            return finder.didFind
        }

        /// A nested type declaration is skipped whole: its own initializers
        /// belong to *it*, and its registration is a declaration the `#if` can
        /// carry in the ordinary way.
        override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
        override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
        override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
        override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
        override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }

        override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
            didFind = true
            return .skipChildren
        }

        override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
            if constructionAttributes.contains(node.name) {
                didFind = true
            }
            return .skipChildren
        }
    }
}
