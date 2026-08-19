//
//  ScopedMacro.swift
//  Zerk
//

import SwiftSyntax
import SwiftSyntaxMacros

/// Inert marker, for the same reason ``SingletonMacro`` is: whether a `@Scoped`
/// can actually be built depends on its whole dependency subtree — an argument
/// it cannot resolve, an effect it cannot run synchronously — and none of that
/// is visible from the one declaration a macro is handed. The checks live in
/// `SourceCollector` and `GeneratorOutputBuilder`.
public struct ScopedMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax,
                                 providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        return []
    }
}
