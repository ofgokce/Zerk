//
//  ImportedInjectableValueMacro.swift
//  Zerk
//

import MacroToolkit
import SharedToolkit
import SwiftSyntax
import SwiftSyntaxMacros

/// Validates `@ImportedInjectableValue` and expands to nothing.
///
/// Unlike ``ImportedInjectableMacro`` this is a peer macro rather than a body
/// macro. It has nothing to synthesise: a value import always names the member
/// it means, since there is no "the primary `String`" to fall back on. The
/// getter the developer wrote is therefore already the check — it resolves the
/// value exactly as the graph will, so an import naming something unexported
/// fails to compile at the declaration.
///
/// What is left is the shape: the key comes from the type annotation and the
/// matching name from the declaration, so both have to be there and readable.
public struct ImportedInjectableValueMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax,
                                 providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let variable = declaration.as(VariableDeclSyntax.self) else {
            context.zerkError(
                node,
                "@ImportedInjectableValue can only be applied to a property. Use @ImportedInjectable to import a key."
            )
            return []
        }

        guard let binding = variable.bindings.first,
              variable.bindings.count == 1,
              binding.pattern.is(IdentifierPatternSyntax.self) else {
            context.zerkError(
                node,
                "@ImportedInjectableValue must declare a single named property. Its name is what parameters match against."
            )
            return []
        }

        guard binding.typeAnnotation != nil else {
            context.zerkError(
                node,
                "@ImportedInjectableValue needs an explicit type — it is the injection key, and Zerk reads syntax so it cannot infer one."
            )
            return []
        }

        // A stored binding would read the foreign value once, at initialization,
        // rather than per resolution. Reported separately from a missing getter
        // because the fix differs: this one is already written, just wrongly.
        if binding.initializer != nil, !binding.hasGetter {
            context.zerkError(
                node,
                "@ImportedInjectableValue reads the other module's value on every resolution, so it needs a getter rather than an assignment. Write '{ \(binding.initializer?.value.trimmedDescription ?? "Zerk<Key>.member") }'."
            )
            return []
        }

        guard binding.hasGetter else {
            context.zerkError(
                node,
                "@ImportedInjectableValue must name the member it imports, e.g. 'static var apiKey: String { Zerk<String>.apiKey }'. There is no primary value for a key to fall back on."
            )
            return []
        }

        // `let` needs no check of its own: Swift rejects a computed `let` before
        // this runs ("'let' declarations cannot be computed properties"), and a
        // `let` with an initializer is caught as an assignment above.
        if binding.importedValueExpression == nil {
            context.zerkError(
                node,
                "@ImportedInjectableValue's getter must be a single Zerk expression, e.g. 'Zerk<String>.apiKey'. Zerk inlines it wherever the value is resolved, so it cannot contain other logic."
            )
        }

        return []
    }
}
