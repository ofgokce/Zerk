//
//  InjectableMacro.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 1.12.2025.
//

import MacroToolkit
import SharedToolkit
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Validates `@Injectable` and expands to nothing.
///
/// Registration happens in the build plugin. What this macro adds is the
/// subset of errors decidable from the declaration alone — the type does not
/// conform to the key it claims, a key is annotated twice, no `@Providing`
/// provider exists — reported at the declaration instead of from generated
/// code the developer did not write.
public struct InjectableMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax,
                                 providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        if let typeDecl = ZerkTypeDecl(declaration) {
            validateInjectableType(typeDecl, node: node, in: context)
        } else if let variableDecl = declaration.as(VariableDeclSyntax.self) {
            validateInjectableVariable(variableDecl, node: node, in: context)
        }
        return []
    }
}

private extension InjectableMacro {
    /// A value provider: `@Injectable static var apiKey: String`.
    ///
    /// Must be `static` when nested in a type — an instance property would need
    /// an instance to read, which the generated registry has no way to obtain.
    static func validateInjectableVariable(_ declaration: VariableDeclSyntax,
                                           node: AttributeSyntax,
                                           in context: some MacroExpansionContext) {
        let injectableAttributes = declaration.attributes.attributes(
            named: ZerkMacroNames.injectableAttributeName
        )

        // A declaration may carry several @Injectable attributes, one per key,
        // and the macro expands once per attribute. Everything below inspects
        // all of them together, so run it on the first expansion only —
        // otherwise every error is reported once per attribute.
        guard let first = injectableAttributes.first, first.id == node.id else {
            return
        }

        let isInsideType = Syntax(declaration).enclosingTypeName != nil
        let isStatic = declaration.modifiers.isStatic

        if isInsideType && !isStatic {
            context.zerkError(
                node,
                "@Injectable values declared inside a type must be marked static."
            )
        }

        var seenKeys = Set<String>()

        for attribute in injectableAttributes {
            let genericArgs = attribute.genericArgumentTypes
            let genericKeys = genericArgs.map(\.normalizedTypeKey)
            let keys = genericKeys.isEmpty ? ["<implicit>"] : genericKeys

            for key in keys {
                if !seenKeys.insert(key).inserted {
                    context.zerkError(
                        attribute,
                        "Duplicate @Injectable annotation for '\(key)'."
                    )
                }
            }

            for expectedType in genericArgs {
                validateVariableTypeCompatibility(
                    declaration,
                    expectedType: expectedType,
                    attribute: attribute,
                    context: context
                )
            }
        }
    }

    /// Rejects `@Injectable<A> static var x: B`.
    ///
    /// Compared as normalized type keys, i.e. by spelling. A value is
    /// registered under the key it claims, so a mismatch would register it
    /// under a type it cannot satisfy.
    static func validateVariableTypeCompatibility(_ declaration: VariableDeclSyntax,
                                                  expectedType: TypeSyntax,
                                                  attribute: AttributeSyntax,
                                                  context: some MacroExpansionContext) {
        let expectedKey = expectedType.normalizedTypeKey

        for binding in declaration.bindings {
            guard let annotation = binding.typeAnnotation else {
                continue
            }

            let actualKey = annotation.type.normalizedTypeKey
            if actualKey != expectedKey {
                context.zerkError(
                    attribute,
                    "@Injectable<\(expectedKey)> does not match declared type '\(actualKey)'."
                )
                return
            }
        }
    }

    /// A type provider: `@Injectable<Storing> final class Store: Storing`.
    ///
    /// Checks that the type conforms to each key it claims (the conformance
    /// must be written in the declaration — the macro cannot see conformances
    /// added in an extension or another module), that no key is claimed twice,
    /// and that every key has a provider: `@Providing<Key>`, a plain
    /// `@Providing`, or a sole initializer used implicitly.
    static func validateInjectableType(_ declaration: ZerkTypeDecl,
                                       node: AttributeSyntax,
                                       in context: some MacroExpansionContext) {
        let injectableAttributes = declaration.attributes.attributes(
            named: ZerkMacroNames.injectableAttributeName
        )

        // A declaration may carry several @Injectable attributes, one per key,
        // and the macro expands once per attribute. Everything below inspects
        // all of them together, so run it on the first expansion only —
        // otherwise every error is reported once per attribute.
        guard let first = injectableAttributes.first, first.id == node.id else {
            return
        }

        var injectableKeys: [String: AttributeSyntax] = [:]

        for attribute in injectableAttributes {
            let genericArgs = attribute.genericArgumentTypes
            let keys = genericArgs.isEmpty ? [TypeSyntax(stringLiteral: declaration.nameText)] : genericArgs

            for arg in keys {
                let key = arg.normalizedTypeKey

                if key != declaration.nameText && !declaration.inheritsOrConforms(to: key) {
                    context.zerkError(
                        attribute,
                        "Type '\(declaration.nameText)' must explicitly conform to '\(key)' in its declaration."
                    )
                }

                if injectableKeys[key] != nil {
                    context.zerkError(
                        attribute,
                        "Duplicate @Injectable annotation for '\(key)'."
                    )
                } else {
                    injectableKeys[key] = attribute
                }
            }
        }

        if injectableKeys.isEmpty {
            return
        }

        let providerInfo = InjectingProviderInfo(
            from: declaration,
            in: context)

        for (key, providers) in providerInfo.typedProviders {
            if providers.count > 1 {
                for provider in providers.dropFirst() {
                    context.zerkError(
                        provider,
                        "Multiple @Providing<\(key)> providers found. Only one is allowed per injectable type."
                    )
                }
            }

            if injectableKeys[key] == nil {
                if let provider = providers.first {
                    context.zerkError(
                        provider,
                        "@Providing<\(key)> is defined, but there is no matching @Injectable<\(key)> on '\(declaration.nameText)'."
                    )
                }
            }
        }

        if providerInfo.defaultProviders.count > 1 {
            for provider in providerInfo.defaultProviders.dropFirst() {
                context.zerkError(
                    provider,
                    "Multiple non-generic @Providing providers found. Only one default provider is allowed."
                )
            }
        }

        for (key, attribute) in injectableKeys {
            if providerInfo.typedProviders[key] != nil {
                continue
            }

            if providerInfo.hasDefaultProvider {
                continue
            }

            if providerInfo.implicitDefaultAvailable {
                continue
            }

            context.zerkError(
                attribute,
                "No @Providing provider found for @Injectable<\(key)>. Mark an initializer or a static factory with @Providing."
            )
        }
    }
}
