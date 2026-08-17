//
//  InjectedMacro.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 28.07.2026.
//

import MacroToolkit
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Expands `@Injected var x: T` into a backing property that resolves `T`.
///
/// The one Zerk macro that generates code, because it can: the resolution
/// expression is `Zerk<Key>.inject()`, which needs only the property's own type.
///
/// The peer uses `@storageRestrictions(initializes:)` (SE-0400) so the backing
/// property *initializes* the original rather than shadowing it. That keeps a
/// value passed to the memberwise initializer winning over the injected
/// default, so a caller can still override what gets injected.
public struct InjectedMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax,
                                 providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let info = InjectedPropertyInfo(
            from: declaration,
            attribute: node,
            macroName: "@Injected",
            allowObservers: true,
            allowLazyModifier: false,
            requiresVar: false,
            requiresInstanceStorage: true,
            context: context
        ) else {
            return []
        }

        let peer: DeclSyntax = """
        private var \(raw: info.backingName): \(raw: info.declaredType) = \(raw: info.expression) {
            @storageRestrictions(initializes: \(raw: info.propertyName))
            init(initialValue) {
                \(raw: info.propertyName) = initialValue
            }
            get {
                \(raw: info.propertyName)
            }
        }
        """
        return [peer]
    }
}
