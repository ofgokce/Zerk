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
/// conform to the key it claims, a key is annotated twice, no
/// `@InjectableProviding` provider exists — reported at the declaration instead
/// of from generated code the developer did not write.
///
/// Values go through ``InjectableValueMacro``; this one only names it.
public struct InjectableMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax,
                                 providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        if let typeDecl = ZerkTypeDecl(declaration) {
            validateInjectableType(typeDecl, node: node, in: context)
        } else if declaration.is(VariableDeclSyntax.self) || declaration.is(FunctionDeclSyntax.self) {
            context.zerkError(
                node,
                "@Injectable registers a type. Use @InjectableValue for a value \u{2014} a type is built by a provider, a value is read from a declaration, and the two are matched differently."
            )
        }
        return []
    }
}

extension InjectableMacro {
    /// `public:` decides an access level the build plugin emits, and it is read
    /// from source rather than evaluated — so an expression Zerk cannot read has
    /// to be reported instead of quietly resolving to "not exported".
    static func nonLiteralPublicMessage(for attributeName: String) -> String {
        "\(attributeName)(public:) requires a 'true' or 'false' literal. Zerk reads this from source and cannot evaluate an expression."
    }
}

private extension InjectableMacro {
    /// A type provider: `@Injectable<Storing> final class Store: Storing`.
    ///
    /// Checks that the type conforms to each key it claims (the conformance
    /// must be written in the declaration — the macro cannot see conformances
    /// added in an extension or another module), that no key is claimed twice,
    /// and that every key has at least one provider:
    /// `@InjectableProviding<Key>`, a plain `@InjectableProviding`, or a sole
    /// initializer used implicitly.
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
        guard context.isFirstAttribute(node, among: injectableAttributes) else {
            return
        }

        for attribute in injectableAttributes {
            if attribute.hasPositionalArgument {
                context.zerkError(
                    attribute,
                    "The injection method applies to @InjectableValue only. A type is built by a provider, not read from a declaration, so there is nothing to copy or reference."
                )
            }
            if attribute.primaryArgument == .nonLiteral {
                context.zerkError(
                    attribute,
                    "@Injectable(primary:) requires a 'true' or 'false' literal. Zerk reads this from source and cannot evaluate an expression."
                )
            }
            if attribute.publicArgument == .nonLiteral {
                context.zerkError(attribute, Self.nonLiteralPublicMessage(for: "@Injectable"))
            }
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

        // Several providers for one key is now the point, not an error. Whether
        // one of them must be `primary` is a module-wide question — it only
        // binds the type that actually wins the key — so `ProviderResolver`
        // asks it and this macro stays silent.
        for (key, providers) in providerInfo.typedProviders {
            if injectableKeys[key] == nil {
                if let provider = providers.first {
                    context.zerkError(
                        provider,
                        "@InjectableProviding<\(key)> is defined, but there is no matching @Injectable<\(key)> on '\(declaration.nameText)'."
                    )
                }
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
                "No @InjectableProviding provider found for @Injectable<\(key)>. Mark an initializer or a static factory with @InjectableProviding."
            )
        }
    }
}
