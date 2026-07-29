//
//  InjectingProviderInfo.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 28.07.2026.
//

import SharedToolkit
import SwiftSyntax
import SwiftSyntaxMacros

/// The `@Providing` declarations on one type, as the macro sees them.
///
/// Covers the same ground as `SourceCollector` but from a single declaration,
/// which is enough to report a missing or duplicated provider at the
/// declaration site instead of from the generated file.
public struct InjectingProviderInfo {
    
    public var defaultProviders: [AttributeSyntax]
    public var typedProviders: [String: [AttributeSyntax]]
    public var initializerCount: Int

    public var hasDefaultProvider: Bool {
        !defaultProviders.isEmpty
    }

    /// Whether the type can fall back to its sole initializer.
    ///
    /// Requires no `@Providing` anywhere — declaring one is a deliberate
    /// choice that a bare initializer must not silently override — and at most
    /// one initializer. Zero counts, because the compiler then synthesizes one.
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

        for member in declaration.members.members {
            if let initializerDecl = member.decl.as(InitializerDeclSyntax.self) {
                initializerCount += 1

                if let attribute = initializerDecl.attributes.firstAttribute(
                    named: ZerkMacroNames.providingAttributeName
                ) {
                    if attribute.genericArgumentTypes.isEmpty {
                        defaultProviders.append(attribute)
                    }
                }
            } else if let functionDecl = member.decl.as(FunctionDeclSyntax.self) {
                guard let attribute = functionDecl.attributes.firstAttribute(
                    named: ZerkMacroNames.providingAttributeName
                ) else {
                    continue
                }

                guard functionDecl.modifiers.isStatic else {
                    continue
                }

                if let arg = attribute.genericArgumentTypes.first {
                    typedProviders[arg.normalizedTypeKey, default: []].append(attribute)
                } else {
                    defaultProviders.append(attribute)
                }
            }
        }

        self.init(
            defaultProviders: defaultProviders,
            typedProviders: typedProviders,
            initializerCount: initializerCount)
    }
}
