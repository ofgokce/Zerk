//
//  InjectableValuesMacro.swift
//  Zerk
//

import MacroToolkit
import SharedToolkit
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Inert marker. Which members it sweeps up depends on their modifiers and type
/// annotations, which the build plugin reads — the macro only rejects the case
/// it can decide alone: an attachment to something that has no members.
public struct InjectableValuesMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax,
                                 providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard ZerkTypeDecl(declaration) != nil else {
            context.zerkError(
                node,
                "@InjectableValues can only be applied to a class, struct, enum, or actor."
            )
            return []
        }
        if node.publicArgument == .nonLiteral {
            context.zerkError(node, InjectableMacro.nonLiteralPublicMessage(for: "@InjectableValues"))
        }
        return []
    }
}

/// Inert marker opting a property out of an enclosing `@InjectableValues`
/// sweep. The build plugin honours it; the macro only rejects the one
/// contradiction visible from a single declaration.
public struct NonInjectableMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax,
                                 providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        if declaration.as(VariableDeclSyntax.self)?
            .attributes.hasAttribute(named: ZerkMacroNames.injectableValueAttributeName) == true {
            context.zerkError(
                node,
                "@NonInjectable contradicts @InjectableValue on the same declaration."
            )
        }
        return []
    }
}
