//
//  InjectedDynamicallyMacro.swift
//  Zerk
//

import MacroToolkit
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Expands `@InjectedDynamically var x: T` into a getter that resolves `T` afresh
/// on every access.
///
/// The **accessor** counterpart to ``InjectedMacro``, which is a *peer* macro.
/// That one adds a stored peer initializing the property once; this one replaces
/// the property's storage with a getter, which is the only shape that can
/// re-resolve — and is why the two live under different attribute names rather
/// than one name with an argument. See the note above the `InjectedDynamically`
/// declarations in `Sources/Zerk/Macros/InjectedMacro.swift`.
///
/// Everything else is shared: `InjectedPropertyInfo` builds the same resolution
/// expression from the same attribute, so a key, a key path, or forwarded
/// arguments mean here exactly what they mean there.
public struct InjectedDynamicallyMacro: AccessorMacro {
    public static func expansion(of node: AttributeSyntax,
                                 providingAccessorsOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [AccessorDeclSyntax] {
        guard let info = InjectedPropertyInfo(
            from: declaration,
            attribute: node,
            macroName: "@InjectedDynamically",
            // A getter replaces the storage outright, so there is none left for
            // an observer to fire on. `requiresVar` for the same reason: a `let`
            // cannot be computed.
            allowObservers: false,
            allowLazyModifier: false,
            requiresVar: true,
            context: context
        ) else {
            return []
        }

        return [
            """
            get {
                \(raw: info.expression)
            }
            """
        ]
    }
}
