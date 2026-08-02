//
//  InjectedPropertyInfo.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 28.07.2026.
//

import Foundation
import SharedToolkit
import SwiftSyntax
import SwiftSyntaxMacros

/// Everything `@Injected` needs to expand one property, plus the validation
/// that rejects shapes it cannot expand.
///
/// The parsing initializer is failable and reports its own diagnostics, so
/// `nil` means an error has already been emitted and the caller should return
/// an empty expansion rather than complain again. The `allow*`/`requires*`
/// flags let one implementation back several property macros at different
/// strictness.
public struct InjectedPropertyInfo {
    public let propertyName: String
    /// Name of the generated peer. Must keep the `_$zerk_injection_` prefix
    /// that the macro declaration lists in `names: prefixed(...)` — a peer
    /// macro may only introduce names it declared up front.
    public let backingName: String
    public let declaredType: String
    /// The type actually looked up, which is `declaredType` with one level of
    /// Optional removed.
    public let injectedType: String
    public let expression: String
    
    init(propertyName: String,
         backingName: String,
         declaredType: String,
         injectedType: String,
         expression: String) {
        self.propertyName = propertyName
        self.backingName = backingName
        self.declaredType = declaredType
        self.injectedType = injectedType
        self.expression = expression
    }

    public init?(from declaration: some DeclSyntaxProtocol,
                 attribute: AttributeSyntax,
                 macroName: String,
                 allowObservers: Bool,
                 allowLazyModifier: Bool,
                 requiresVar: Bool,
                 context: some MacroExpansionContext) {
        
        guard let variableDecl = declaration.as(VariableDeclSyntax.self) else {
            context.zerkError(attribute, "\(macroName) can only be applied to a variable declaration.")
            return nil
        }

        guard variableDecl.bindings.count == 1,
              let binding = variableDecl.bindings.first else {
            context.zerkError(attribute, "\(macroName) can only be applied to a single variable binding.")
            return nil
        }

        if !allowLazyModifier,
           variableDecl.modifiers.hasModifier(named: "lazy") {
            context.zerkError(attribute, "\(macroName) should not be combined with the 'lazy' modifier.")
            return nil
        }

        if requiresVar && variableDecl.bindingSpecifier.text != "var" {
            context.zerkError(attribute, "\(macroName) can only be applied to 'var' declarations.")
            return nil
        }

        if !Self.hasSupportedAccessors(binding.accessorBlock, allowObservers: allowObservers) {
            let message = allowObservers
                ? "\(macroName) properties may only define willSet/didSet observers."
                : "\(macroName) cannot be applied to a property that already defines accessors."
            context.zerkError(attribute, message)
            return nil
        }

        guard binding.initializer == nil else {
            context.zerkError(attribute, "\(macroName) properties should not define an explicit initializer.")
            return nil
        }

        guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
            context.zerkError(attribute, "\(macroName) can only be applied to an identifier pattern.")
            return nil
        }

        guard let typeAnnotation = binding.typeAnnotation else {
            context.zerkError(attribute, "\(macroName) properties must declare an explicit type.")
            return nil
        }

        let info = InjectedAttributeInfo(from: attribute)
        if info.genericArguments.count > 1 {
            context.zerkError(attribute, "\(macroName) accepts at most one generic argument.")
        }

        let declaredType = typeAnnotation.type.trimmedDescription
        let actualKey = typeAnnotation.type.normalizedTypeKey
        let injectedType = Self.injectedTypeName(from: declaredType)
        // Derived from the canonical key rather than from `injectedType`, which
        // is a spelling meant for emission. Comparing a raw spelling against a
        // canonical one would reject `@Injected<Array<String>> var x: [String]?`.
        let injectedKey = Self.unwrappingOptional(actualKey)

        if let expectedType = info.genericArguments.first {
            let expectedKey = expectedType.normalizedTypeKey
            if expectedKey != actualKey && expectedKey != injectedKey {
                context.zerkError(
                    attribute,
                    "\(macroName)<\(expectedKey)> does not match declared type '\(actualKey)'."
                )
                return nil
            }
        }

        let expression = info.explicitExpression ?? Self.buildInjectedExpression(
            injectedType: injectedType,
            arguments: info.callArguments)

        self.init(
            propertyName: identifier.identifier.text,
            backingName: "_$zerk_injection_\(identifier.identifier.text)",
            declaredType: declaredType,
            injectedType: injectedType,
            expression: expression)
    }

    /// A property with a getter is computed: there is no storage to initialize,
    /// so there is nothing to inject. `willSet`/`didSet` are permitted because
    /// they observe storage rather than replace it.
    private static func hasSupportedAccessors(_ accessorBlock: AccessorBlockSyntax?,
                                              allowObservers: Bool) -> Bool {
        guard let accessorBlock else {
            return true
        }

        guard allowObservers else {
            return false
        }

        switch accessorBlock.accessors {
        case .getter:
            return false
        case .accessors(let accessors):
            return accessors.allSatisfy { accessor in
                let name = accessor.accessorSpecifier.text
                return name == "willSet" || name == "didSet"
            }
        }
    }

    /// Builds `Zerk<T>.inject()`, forwarding any attribute arguments verbatim.
    private static func buildInjectedExpression(injectedType: String,
                                                arguments: [LabeledExprSyntax]) -> String {
        let target = "Zerk<\(injectedType)>.inject"
        guard !arguments.isEmpty else {
            return "\(target)()"
        }

        let argumentList = arguments.map(\.trimmedDescription).joined(separator: ", ")
        return "\(target)(\(argumentList))"
    }

    /// Strips one level of Optional, so `@Injected var x: Foo?` resolves `Foo`
    /// rather than looking for a registered `Foo?`.
    ///
    /// Both spellings are handled, `Foo?`/`Foo!` and `Optional<Foo>`. The
    /// property keeps its declared type; only the lookup key is unwrapped.
    private static func injectedTypeName(from declaredType: String) -> String {
        let trimmed = declaredType.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("?") || trimmed.hasSuffix("!") {
            return String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if trimmed.hasPrefix("Optional<"), trimmed.hasSuffix(">") {
            let start = trimmed.index(trimmed.startIndex, offsetBy: "Optional<".count)
            let end = trimmed.index(before: trimmed.endIndex)
            return String(trimmed[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }

    /// Strips one `Optional<…>` layer from an already-canonical key.
    ///
    /// Canonicalization has folded `Foo?`, `Foo!` and `Optional<Foo>` into one
    /// spelling by this point, so this is the only shape left to unwrap.
    private static func unwrappingOptional(_ key: String) -> String {
        guard key.hasPrefix("Optional<"), key.hasSuffix(">") else {
            return key
        }
        return String(key.dropFirst("Optional<".count).dropLast())
    }
}
