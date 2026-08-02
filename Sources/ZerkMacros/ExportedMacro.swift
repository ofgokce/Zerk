//
//  ExportedMacro.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 8.02.2026.
//

import SwiftSyntax
import SwiftSyntaxMacros

/// Inert marker. `@Exported` raises the access level of the members generated
/// for a key, which only the build plugin knows how to emit — and whether the
/// key is public enough to allow it is a module-wide fact, not a property of
/// this declaration.
public struct ExportedMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax,
                                 providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        return []
    }
}
