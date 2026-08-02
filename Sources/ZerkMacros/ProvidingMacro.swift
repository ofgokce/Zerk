//
//  ProvidingMacro.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 2.12.2025.
//

import MacroToolkit
import SharedToolkit
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Marks an initializer or static factory that builds an `@Injectable`.
///
/// Semantically inert: it validates, then returns the declaration's own
/// statements unchanged, so the body a developer wrote is the body that runs.
/// The build plugin reads the marked declaration's signature to work out what
/// the type depends on.
///
/// A type may carry several of these for one key. Which of them `inject()`
/// calls is settled module-wide by `ProviderResolver`, not here — this macro
/// sees one declaration and cannot know whether it has competition.
public struct ProvidingMacro: BodyMacro {
    public static func expansion(of node: AttributeSyntax,
                                 providingBodyFor declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
                                 in context: some MacroExpansionContext) throws -> [CodeBlockItemSyntax] {
        validateUsage(node: node, declaration: declaration, context: context)

        if let body = declaration.body {
            return Array(body.statements)
        }
        return []
    }
}

private extension ProvidingMacro {
    /// A provider must be callable without an instance and must return one:
    /// an initializer, or a `static` function with a non-`Void` return type.
    ///
    /// The key a provider satisfies comes from `@InjectableProviding<Key>`. An
    /// initializer cannot take one, because it can only ever produce its own
    /// type — the key is then whatever `@Injectable` claims.
    static func validateUsage(node: AttributeSyntax,
                              declaration: some DeclSyntaxProtocol,
                              context: some MacroExpansionContext) {
        validatePrimaryArgument(node: node, context: context)

        let genericArgs = node.genericArgumentTypes

        if declaration.as(InitializerDeclSyntax.self) != nil {
            if !genericArgs.isEmpty {
                context.zerkError(
                    node,
                    "@InjectableProviding with a generic argument is not supported on initializers."
                )
            }
            return
        }

        if let functionDecl = declaration.as(FunctionDeclSyntax.self) {
            if !functionDecl.modifiers.isStatic {
                context.zerkError(
                    node,
                    "@InjectableProviding on a function requires the function to be static."
                )
            }

            if let returnType = functionDecl.signature.returnClause?.type {
                if isVoidType(returnType) {
                    context.zerkError(
                        node,
                        "@InjectableProviding functions must return a value."
                    )
                }
            } else {
                context.zerkError(
                    node,
                    "@InjectableProviding functions must declare a return type."
                )
            }
            return
        }

        context.zerkError(
            node,
            "@InjectableProviding can only be applied to an initializer or a static function."
        )
    }

    /// The build plugin decides which provider `inject()` calls by reading
    /// `primary:` out of the source text, so anything it cannot read there —
    /// a constant, a flag, a function call — would silently resolve to
    /// "not primary" and quietly change which implementation ships.
    static func validatePrimaryArgument(node: AttributeSyntax,
                                        context: some MacroExpansionContext) {
        guard node.primaryArgument == .nonLiteral else {
            return
        }
        context.zerkError(
            node,
            "@InjectableProviding(primary:) requires a 'true' or 'false' literal. Zerk reads this from source and cannot evaluate an expression."
        )
    }

    /// `()` canonicalizes to `Void`, so one comparison covers both spellings.
    static func isVoidType(_ type: TypeSyntax) -> Bool {
        type.normalizedTypeKey == "Void"
    }
}
