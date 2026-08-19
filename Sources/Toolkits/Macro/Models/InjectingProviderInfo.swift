//
//  InjectingProviderInfo.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 28.07.2026.
//

import SharedToolkit
import SwiftSyntax
import SwiftSyntaxMacros

/// The `@InjectableProviding` declarations on one type, as the macro sees them.
///
/// Covers the same ground as `SourceCollector` but from a single declaration,
/// which is enough to report a missing provider, or one bound to a key the type
/// does not claim, at the declaration site instead of from the generated file.
///
/// It cannot report *ambiguity*: several providers for one key are legal, and
/// whether one of them has to be `primary` depends on which type wins the key
/// module-wide — which only `ProviderResolver` can see.
public struct InjectingProviderInfo {
    
    public var defaultProviders: [AttributeSyntax]
    public var typedProviders: [String: [AttributeSyntax]]
    public var initializerCount: Int

    public var hasDefaultProvider: Bool {
        !defaultProviders.isEmpty
    }

    /// Whether the type can fall back to its sole initializer.
    ///
    /// Requires no `@InjectableProviding` anywhere — declaring one is a
    /// deliberate choice that a bare initializer must not silently override —
    /// and at most one initializer. Zero counts, because the compiler then
    /// synthesizes one.
    public var implicitDefaultAvailable: Bool {
        typedProviders.isEmpty && defaultProviders.isEmpty && initializerCount <= 1
    }
    
    init(defaultProviders: [AttributeSyntax], typedProviders: [String : [AttributeSyntax]], initializerCount: Int) {
        self.defaultProviders = defaultProviders
        self.typedProviders = typedProviders
        self.initializerCount = initializerCount
    }

    public init(from declaration: ZerkTypeDecl,
                in context: some MacroExpansionContext) {
        
        var defaultProviders: [AttributeSyntax] = []
        var typedProviders: [String: [AttributeSyntax]] = [:]
        var initializerCount = 0

        // Every matching attribute, not just the first: one factory can be
        // bound to several keys at once with repeated
        // `@InjectableProviding<A> @InjectableProviding<B>`, and a key whose
        // attribute went unread would be reported as having no provider.
        for member in declaration.members.members {
            if let initializerDecl = member.decl.as(InitializerDeclSyntax.self) {
                initializerCount += 1

                for attribute in initializerDecl.attributes.attributes(
                    named: ZerkMacroNames.injectableProvidingAttributeName
                ) where attribute.genericArgumentTypes.isEmpty {
                    defaultProviders.append(attribute)
                }
            } else if let functionDecl = member.decl.as(FunctionDeclSyntax.self) {
                guard functionDecl.modifiers.isStatic else {
                    continue
                }

                for attribute in functionDecl.attributes.attributes(
                    named: ZerkMacroNames.injectableProvidingAttributeName
                ) {
                    let keys = attribute.genericArgumentTypes
                    if keys.isEmpty {
                        defaultProviders.append(attribute)
                        continue
                    }
                    for key in keys {
                        typedProviders[key.normalizedTypeKey, default: []].append(attribute)
                    }
                }
            }
        }

        self.init(
            defaultProviders: defaultProviders,
            typedProviders: typedProviders,
            initializerCount: initializerCount)
    }
}
