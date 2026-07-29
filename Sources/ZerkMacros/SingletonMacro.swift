//
//  SingletonMacro.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 1.12.2025.
//

import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Inert marker. Whether a `@Singleton` can actually be built — its storage is
/// initialized synchronously, so a dependency it has to `await` disqualifies it
/// — depends on the whole graph, so the check lives in `GeneratorOutputBuilder`.
public struct SingletonMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax,
                                 providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        return []
    }
}
