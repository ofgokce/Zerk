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
        } else if let ext = declaration.as(ExtensionDeclSyntax.self) {
            context.zerkError(
                node,
                InjectableRefusal.extensionTarget(extending: ext.extendedType.trimmedDescription)
            )
        } else if declaration.is(VariableDeclSyntax.self) || declaration.is(FunctionDeclSyntax.self) {
            // A global or static declaration registers the type it produces,
            // with itself as the provider. Whether it is *placed* somewhere the
            // generated file can reach is a question about its surroundings,
            // which a macro cannot see — the plugin settles that. What is
            // decidable here is the attribute's own arguments.
            validateInjectableDeclaration(node, in: context)
        }
        return []
    }
}

private extension InjectableMacro {
    /// `@Injectable` on a var or func: the arguments that name the generated
    /// member cannot both be given, and neither can be an expression.
    static func validateInjectableDeclaration(_ node: AttributeSyntax,
                                              in context: some MacroExpansionContext) {
        if node.typeNamedArgument == .nonLiteral {
            context.zerkError(node, MemberNamingRefusal.nonLiteralTypeNamed(attribute: "@Injectable"))
            return
        }
        if node.nameArgument == .nonLiteral {
            context.zerkError(node, MemberNamingRefusal.nonLiteralName(attribute: "@Injectable"))
            return
        }
        if node.typeNamedArgument.isTrue, let name = node.nameArgument.value {
            context.zerkError(
                node,
                MemberNamingRefusal.conflictingNames(attribute: "@Injectable", name: name)
            )
        }
    }

    /// One provider the plugin will turn into a member, reduced to what a
    /// generic-parameter check needs.
    struct ProviderSignature {
        let name: String?
        let parameters: [FunctionParameterSyntax]
        /// The provider's *own* generic parameters, beyond the type's.
        let genericParameters: [String]
        let node: Syntax
    }

    /// Every provider on this declaration: the marked initializers and static
    /// factories, or the sole initializer when nothing is marked.
    ///
    /// Mirrors `ProviderResolver`'s fallback rather than reusing it — the
    /// resolver works from collected records and cannot be reached from a macro,
    /// which sees one declaration. The two agreeing is what makes this check
    /// worth having: it says the same thing, at the declaration.
    static func providerSignatures(of declaration: ZerkTypeDecl) -> [ProviderSignature] {
        var marked: [ProviderSignature] = []
        var initializers: [ProviderSignature] = []

        for member in declaration.members.members {
            if let initializer = member.decl.as(InitializerDeclSyntax.self) {
                let signature = ProviderSignature(
                    name: nil,
                    parameters: Array(initializer.signature.parameterClause.parameters),
                    genericParameters: initializer.genericParameterClause?
                        .parameters.map { $0.name.text } ?? [],
                    node: Syntax(initializer))
                initializers.append(signature)
                if initializer.attributes.hasAttribute(
                    named: ZerkMacroNames.injectableProvidingAttributeName) {
                    marked.append(signature)
                }
            } else if let function = member.decl.as(FunctionDeclSyntax.self),
                      function.attributes.hasAttribute(
                        named: ZerkMacroNames.injectableProvidingAttributeName) {
                marked.append(ProviderSignature(
                    name: function.name.text,
                    parameters: Array(function.signature.parameterClause.parameters),
                    genericParameters: function.genericParameterClause?
                        .parameters.map { $0.name.text } ?? [],
                    node: Syntax(function)))
            }
        }

        if !marked.isEmpty {
            return marked
        }
        // The synthesized memberwise initializer is not visible here, so a
        // struct relying on it is left to the plugin, which can see the stored
        // properties.
        return initializers.count == 1 ? initializers : []
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

        // A generic type registers under itself, and only under itself. The two
        // shapes that have no legal form are reported before anything else, and
        // alone: every check below is about a key this type is not going to
        // have. See ``GenericRefusal``.
        let genericParameters = declaration.genericParameterNames

        // `parameterized:` applies the type's parameters to the key, so a type
        // with none has nothing to apply. Checked ahead of everything else,
        // since the key it describes does not exist.
        for attribute in injectableAttributes where attribute.parameterizedArgument != .absent {
            if attribute.parameterizedArgument == .nonLiteral {
                context.zerkError(
                    attribute,
                    "@Injectable(parameterized:) requires a 'true' or 'false' literal. Zerk reads this from source and cannot evaluate an expression."
                )
                return
            }
            guard attribute.parameterizedArgument.isTrue else {
                continue
            }
            if genericParameters.isEmpty {
                context.zerkError(
                    attribute,
                    GenericRefusal.parameterizedNonGeneric(type: declaration.nameText)
                )
                return
            }
            if attribute.genericArgumentDisplayKeys.first == nil {
                context.zerkError(
                    attribute,
                    GenericRefusal.parameterizedNeedsExistentialKey(
                        type: declaration.nameText, key: nil)
                )
                return
            }
        }

        // A parameter the provider declares itself is unreachable unless one of
        // its own arguments mentions it — true whatever the key is, so this runs
        // for a non-generic type too.
        for provider in Self.providerSignatures(of: declaration) where !provider.genericParameters.isEmpty {
            let scope = Set(genericParameters + provider.genericParameters)
            let bound = Set(provider.parameters.flatMap {
                $0.type.mentionedGenericParameters(in: scope)
            })
            let unbound = provider.genericParameters.filter { !bound.contains($0) }
            guard !unbound.isEmpty else {
                continue
            }
            context.zerkError(
                provider.node,
                GenericRefusal.unboundProviderParameters(on: declaration.nameText,
                                                         provider: provider.name,
                                                         parameters: unbound)
            )
            return
        }

        if !genericParameters.isEmpty {
            if declaration.attributes.hasAttribute(named: ZerkMacroNames.singletonAttributeName) {
                context.zerkError(node, GenericRefusal.singleton(type: declaration.nameText))
                return
            }
            // A written key erases the type's parameters, so every provider has
            // to recover them from its own arguments. The build plugin settles
            // this per resolution; the same answer is decidable from this
            // declaration alone, so it is reported here too.
            //
            // `parameterized: true` is the exception: there the key *carries* the
            // parameters rather than erasing them, so nothing has to recover
            // them and the check does not apply.
            for attribute in injectableAttributes {
                guard let key = attribute.genericArgumentDisplayKeys.first else {
                    continue
                }
                if attribute.parameterizedArgument.isTrue {
                    guard key.hasPrefix("any ") else {
                        context.zerkError(
                            attribute,
                            GenericRefusal.parameterizedNeedsExistentialKey(
                                type: declaration.nameText, key: key)
                        )
                        return
                    }
                    continue
                }
                for provider in Self.providerSignatures(of: declaration) {
                    let scope = Set(genericParameters + provider.genericParameters)
                    let bound = Set(provider.parameters.flatMap {
                        $0.type.mentionedGenericParameters(in: scope)
                    })
                    let unbound = genericParameters.filter { !bound.contains($0) }
                    guard !unbound.isEmpty else {
                        continue
                    }
                    context.zerkError(
                        provider.node,
                        GenericRefusal.unboundKeyParameters(on: declaration.nameText,
                                                            key: key,
                                                            provider: provider.name,
                                                            parameters: unbound)
                    )
                    return
                }
            }
        }

        for attribute in injectableAttributes {
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

                // Conformance is deliberately *not* checked here. Reading
                // syntax, Zerk sees only what the declaration itself lists — not
                // a conformance added in an extension, inherited transitively,
                // or declared in another module — so the check refused code that
                // was correct, and a parameterized spelling (`Box<X, Y>: Boxable<X, Y>`)
                // failed it outright. The compiler settles the same question on
                // the generated member, with both real types named and no false
                // positives.

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
        // Sorted: dictionary order is unspecified and varies between
        // processes, so several bad keys on one declaration would be reported
        // in a different order on each compilation.
        for key in providerInfo.typedProviders.keys.sorted() {
            let providers = providerInfo.typedProviders[key]!
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
