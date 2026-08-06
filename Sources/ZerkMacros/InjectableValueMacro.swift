//
//  InjectableValueMacro.swift
//  Zerk
//

import MacroToolkit
import SharedToolkit
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Validates `@InjectableValue` and expands to nothing.
///
/// Split out of ``InjectableMacro`` because a value is not a type with a
/// different storage: it is matched by key *and* name, has no `inject()` and no
/// providers, and takes a ``ValueInjectionMethod`` a type has no use for. One
/// macro serving both meant every argument had to be checked against the
/// declaration kind at expansion time; two mean the wrong argument does not
/// type-check in the first place.
public struct InjectableValueMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax,
                                 providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        if let variable = declaration.as(VariableDeclSyntax.self) {
            validate(variable, node: node, in: context)
        } else if let function = declaration.as(FunctionDeclSyntax.self) {
            validate(function, node: node, in: context)
        } else if ZerkTypeDecl(declaration) != nil {
            context.zerkError(
                node,
                "@InjectableValue registers a value. Use @Injectable to register the type itself, or @InjectableValues to sweep up its static properties."
            )
        }
        return []
    }
}

private extension InjectableValueMacro {

    /// The attribute spelling, so the checks below and the build plugin cannot
    /// drift apart.
    static let attributeName = "InjectableValue"

    /// Shared by both forms: `primary:` belongs to types, and `public:` has to be
    /// readable from source.
    ///
    /// A declaration may carry several attributes, one per key, and the macro
    /// expands once per attribute — so callers run this on the first expansion
    /// only, or every error is reported once per attribute.
    static func validateArguments(_ attributes: [AttributeSyntax],
                                  in context: some MacroExpansionContext) {
        for attribute in attributes {
            if attribute.primaryArgument != .absent {
                context.zerkError(
                    attribute,
                    "'primary' applies to types only. A value is the sole provider for its key, so there is nothing to be primary over."
                )
            }
            if attribute.publicArgument == .nonLiteral {
                context.zerkError(
                    attribute,
                    InjectableMacro.nonLiteralPublicMessage(for: "@InjectableValue")
                )
            }
        }
    }

    /// Rejects the same key claimed twice across a declaration's attributes.
    static func validateDistinctKeys(_ attributes: [AttributeSyntax],
                                     in context: some MacroExpansionContext) {
        var seen = Set<String>()
        for attribute in attributes {
            let genericKeys = attribute.genericArgumentKeys
            for key in genericKeys.isEmpty ? ["<implicit>"] : genericKeys where !seen.insert(key).inserted {
                context.zerkError(attribute, "Duplicate @InjectableValue annotation for '\(key)'.")
            }
        }
    }

    // MARK: - Property form

    /// `@InjectableValue static var apiKey: String`.
    ///
    /// Must be `static` when nested in a type — an instance property would need
    /// an instance to read, which the generated registry has no way to obtain.
    static func validate(_ declaration: VariableDeclSyntax,
                         node: AttributeSyntax,
                         in context: some MacroExpansionContext) {
        let attributes = declaration.attributes.attributes(named: attributeName)
        guard context.isFirstAttribute(node, among: attributes) else {
            return
        }

        if Syntax(declaration).enclosingTypeName != nil, !declaration.modifiers.isStatic {
            context.zerkError(
                node,
                "@InjectableValue properties declared inside a type must be marked static."
            )
        }

        validateArguments(attributes, in: context)
        validateDistinctKeys(attributes, in: context)

        for attribute in attributes {
            for expectedType in attribute.genericArgumentTypes {
                validateTypeCompatibility(declaration, expectedType: expectedType, attribute: attribute, context: context)
            }
        }
    }

    /// Rejects `@InjectableValue<A> static var x: B`.
    ///
    /// Compared as normalized type keys, i.e. by spelling. A value is registered
    /// under the key it claims, so a mismatch would register it under a type it
    /// cannot satisfy.
    static func validateTypeCompatibility(_ declaration: VariableDeclSyntax,
                                          expectedType: TypeSyntax,
                                          attribute: AttributeSyntax,
                                          context: some MacroExpansionContext) {
        let expectedKey = expectedType.normalizedTypeKey

        for binding in declaration.bindings {
            guard let annotation = binding.typeAnnotation else {
                continue
            }
            if annotation.type.normalizedTypeKey != expectedKey {
                context.zerkError(
                    attribute,
                    "@InjectableValue<\(expectedKey)> does not match declared type '\(annotation.type.normalizedTypeKey)'."
                )
                return
            }
        }
    }

    // MARK: - Functions

    /// `@InjectableValue` on a function, which is refused.
    ///
    /// Decidable from the declaration alone, so it is reported here as well as
    /// by the plugin — see ``InjectableValueRefusal/functionTarget``.
    static func validate(_ declaration: FunctionDeclSyntax,
                         node: AttributeSyntax,
                         in context: some MacroExpansionContext) {
        let attributes = declaration.attributes.attributes(named: attributeName)
        guard context.isFirstAttribute(node, among: attributes) else {
            return
        }
        context.zerkError(node, InjectableValueRefusal.functionTarget)
    }
}
