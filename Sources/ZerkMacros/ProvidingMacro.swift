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

/// Marks the initializer or static factory that builds an `@Injectable`.
///
/// Semantically inert: it validates, then returns the declaration's own
/// statements unchanged, so the body a developer wrote is the body that runs.
/// The build plugin reads the marked declaration's signature to work out what
/// the type depends on.
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
    /// The key a provider satisfies comes from `@Providing<Key>`. An
    /// initializer cannot take one, because it can only ever produce its own
    /// type — the key is then whatever `@Injectable` claims.
    static func validateUsage(node: AttributeSyntax,
                              declaration: some DeclSyntaxProtocol,
                              context: some MacroExpansionContext) {
        let genericArgs = node.genericArgumentTypes

        if declaration.as(InitializerDeclSyntax.self) != nil {
            if !genericArgs.isEmpty {
                context.zerkError(
                    node,
                    "@Providing with a generic argument is not supported on initializers."
                )
            }
            return
        }

        if let functionDecl = declaration.as(FunctionDeclSyntax.self) {
            if !functionDecl.modifiers.isStatic {
                context.zerkError(
                    node,
                    "@Providing on a function requires the function to be static."
                )
            }

            if let returnType = functionDecl.signature.returnClause?.type {
                if isVoidType(returnType) {
                    context.zerkError(
                        node,
                        "@Providing functions must return a value."
                    )
                }
            } else {
                context.zerkError(
                    node,
                    "@Providing functions must declare a return type."
                )
            }
            return
        }

        context.zerkError(
            node,
            "@Providing can only be applied to an initializer or a static function."
        )
    }

    static func isVoidType(_ type: TypeSyntax) -> Bool {
        let key = type.normalizedTypeKey
        return key == "Void" || key == "()"
    }
}
