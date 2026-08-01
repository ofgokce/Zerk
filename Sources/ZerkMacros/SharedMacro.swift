//
//  SharedMacro.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 8.02.2026.
//

import MacroToolkit
import SharedToolkit
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Inert marker. `@Shared` means "reuse one instance per resolution chain", a
/// property of the graph rather than of this declaration, so the build plugin
/// acts on it.
public struct SharedMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax,
                                 providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        return []
    }
}

/// Inert marker. The build plugin reads the generic argument; the macro only
/// checks that one was supplied and that it is not contradicted on the spot.
public struct IsolatedMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax,
                                 providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        let arguments = node.genericArgumentTypes

        guard let first = arguments.first else {
            context.zerkError(
                node,
                "@Isolated requires a global actor type argument, e.g. @Isolated<MainActor>."
            )
            return []
        }

        if arguments.count > 1 {
            context.zerkError(
                node,
                "@Isolated accepts exactly one global actor type argument."
            )
        }

        let actorName = first.normalizedTypeKey

        if declaration.modifiers?.hasModifier(named: "nonisolated") == true {
            context.zerkError(
                node,
                "@Isolated<\(actorName)> contradicts the 'nonisolated' modifier on the same declaration."
            )
        }

        return []
    }
}
