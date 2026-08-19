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
    /// - Parameter consultsInference: whether the enclosing declaration's
    ///   initializer is *inferred*. A type that declares its own initializer or
    ///   an `@InjectableProviding` member is built from what it wrote, so a
    ///   conditional stored property changes nothing Zerk reads — and an
    ///   extension cannot hold stored properties at all.
    static func gatesConstruction(_ node: IfConfigDeclSyntax,
                                  consultsInference: Bool) -> Bool {
        Finder.found(in: Syntax(node), consultsInference: consultsInference)
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
        private let consultsInference: Bool

        init(viewMode: SyntaxTreeViewMode, consultsInference: Bool) {
            self.consultsInference = consultsInference
            super.init(viewMode: viewMode)
        }

        static func found(in node: Syntax, consultsInference: Bool) -> Bool {
            let finder = Finder(viewMode: .sourceAccurate, consultsInference: consultsInference)
            finder.walk(node)
            return finder.didFind
        }

        /// A stored property matters only when it would be a *required*
        /// parameter — which is the same test `unreadableStoredProperty` makes,
        /// and deliberately so: this check exists to protect the inference, so
        /// it must not refuse what the inference would have handled.
        ///
        /// Skipped, therefore: a property with a value of its own (a struct's
        /// memberwise initializer defaults it, and a class still synthesizes
        /// `init()`), a computed one, a static one, and one whose macro
        /// satisfies its own storage — `@Injected` and `@InjectedDynamically`
        /// are not parameters anywhere else either.
        override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
            guard consultsInference,
                  !node.modifiers.isStatic,
                  !node.attributes.satisfiesItsOwnStorage else {
                return .skipChildren
            }
            for binding in node.bindings
            where binding.initializer == nil && binding.accessorBlock == nil {
                didFind = true
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

        /// An initializer decides how the *enclosing type* is built — but only
        /// where Zerk would read it. In an extension it would not: an extension
        /// cannot hold stored properties, so nothing there is inferred, and an
        /// extension initializer is collected only when it carries markers,
        /// which the parameter check below catches on its own.
        ///
        /// `consultsInference` says which case this is, and it is already false
        /// for an extension.
        override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
            let markers = node.signature.parameterClause.parameters.contains { parameter in
                parameter.attributes.contains { element in
                    guard case .attribute(let attribute) = element else { return false }
                    return ConditionalCompilation.markerAttributes.contains(attribute.name)
                }
            }
            if consultsInference || markers {
                didFind = true
            }
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
