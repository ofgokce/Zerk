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

    /// Whether a `#if` inside a type body gates something Zerk reads off the
    /// type's members.
    ///
    /// Three kinds qualify, and they are three different ways the same mistake
    /// shows up:
    ///
    /// - an **initializer** or an `@InjectableProviding` member, which decides
    ///   how the type is built;
    /// - a **stored property**, because a struct's memberwise initializer is
    ///   shaped by them and `inferredStructInitializer` reads the member list
    ///   without descending into a `#if` — so a conditional one silently
    ///   disappears from the parameters Zerk thinks exist;
    /// - a member carrying **`@injected` parameters**, whose generated overload
    ///   is likewise assembled by walking the member list, and which was being
    ///   dropped without a word.
    ///
    /// Anything with no Zerk meaning at all — a conditional method with no
    /// markers, a computed property, a `#if` around an import — is none of
    /// Zerk's business and passes through untouched.
    static func gatesConstruction(_ node: IfConfigDeclSyntax, in kind: MarkedTypeKind?) -> Bool {
        Finder.found(in: Syntax(node), typeKind: kind)
    }

    /// Attributes that make a member a provider of its enclosing type, or that
    /// make Zerk generate something from it.
    static let constructionAttributes: Set<String> = ["InjectableProviding"]

    /// The parameter markers, whose declarations Zerk rewrites into an overload.
    static let markerAttributes: Set<String> = [
        "injected", "autoinjected", "injectable"
    ]

    private final class Finder: SyntaxVisitor {
        private var didFind = false
        private let typeKind: MarkedTypeKind?

        init(viewMode: SyntaxTreeViewMode, typeKind: MarkedTypeKind?) {
            self.typeKind = typeKind
            super.init(viewMode: viewMode)
        }

        static func found(in node: Syntax, typeKind: MarkedTypeKind?) -> Bool {
            let finder = Finder(viewMode: .sourceAccurate, typeKind: typeKind)
            finder.walk(node)
            return finder.didFind
        }

        /// A stored property shapes a struct's memberwise initializer, and a
        /// class's `init()` when it has no value of its own. A computed one —
        /// an accessor block — shapes neither.
        override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
            guard !node.modifiers.isStatic else {
                return .skipChildren
            }
            for binding in node.bindings where binding.accessorBlock == nil {
                switch typeKind {
                case .structKind:
                    didFind = true
                default:
                    // A class synthesizes `init()` only when every stored
                    // property already holds a value, so a defaulted one
                    // changes nothing.
                    if binding.initializer == nil { didFind = true }
                }
            }
            return .skipChildren
        }

        override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
            // Checked here rather than left to `visit(AttributeSyntax)`, because
            // this returns `.skipChildren` — a provider's own attribute would
            // otherwise never be reached.
            let isProvider = node.attributes.contains { element in
                guard case .attribute(let attribute) = element else { return false }
                return ConditionalCompilation.constructionAttributes.contains(attribute.name)
            }
            // A method with no Zerk attribute is only its business when it
            // carries markers — and then its overload is generated from the
            // member list, which does not see inside this block.
            let markers = node.signature.parameterClause.parameters.contains { parameter in
                parameter.attributes.contains { element in
                    guard case .attribute(let attribute) = element else { return false }
                    return ConditionalCompilation.markerAttributes.contains(attribute.name)
                }
            }
            if isProvider || markers {
                didFind = true
            }
            return .skipChildren
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
