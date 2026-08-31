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

    /// Why an observed property cannot be injected, and what to do instead.
    ///
    /// Shared because both expansions of one observed property report it, and a
    /// developer who sees them both should not have to work out that they are
    /// the same problem.
    static func observedPropertyMessage(_ macroName: String) -> String {
        "\(macroName) cannot resolve an observed property: @Observable rewrites it into a computed property, and \(macroName) initializes stored storage. Mark the property '@ObservationIgnored', which excludes it from observation and leaves it stored."
    }

    /// - Parameter requiresInstanceStorage: whether the macro initializes the
    ///   property's storage rather than replacing it with a getter. Only the
    ///   storage-initializing form needs an instance to initialize; see the
    ///   check itself for what goes wrong without one.
    public init?(from declaration: some DeclSyntaxProtocol,
                 attribute: AttributeSyntax,
                 macroName: String,
                 allowObservers: Bool,
                 allowLazyModifier: Bool,
                 requiresVar: Bool,
                 requiresInstanceStorage: Bool = false,
                 context: some MacroExpansionContext) {

        guard let variableDecl = declaration.as(VariableDeclSyntax.self) else {
            context.zerkError(attribute, "\(macroName) can only be applied to a variable declaration.")
            return nil
        }

        // `@storageRestrictions(initializes:)` hooks the moment an *instance*
        // initializes its stored properties. A `static` or file-scope property
        // has no such moment, so the peer never initializes anything and the
        // declaration is left as written — with no initializer. The compiler
        // then reports "requires an initializer expression or an explicitly
        // stated getter", which names neither Zerk nor the fix, on a
        // declaration that looks exactly like the supported one.
        if requiresInstanceStorage {
            if variableDecl.modifiers.isStatic {
                context.zerkError(attribute, "\(macroName) resolves while its enclosing value is being initialized, and a type-level property has no such moment. Write 'static let \(Self.name(of: variableDecl) ?? "property") = Zerk<Key>.inject()', or use @InjectedDynamically to resolve on each access.")
                return nil
            }
            let isObservationIgnored = variableDecl.attributes
                .hasAttribute(named: "ObservationIgnored")

            // A property wrapper owns its own storage, and this macro
            // initializes storage — so there is nothing here to initialize. The
            // compiler says so as "init accessor cannot refer to property",
            // naming a macro expansion rather than the wrapper, which is the one
            // thing that would explain it.
            //
            // The wrapper's own initializer takes the resolved value directly,
            // so the fix is a spelling rather than a redesign.
            if let wrapper = variableDecl.attributes.firstWrappedValueAttributeName {
                context.zerkError(attribute, "\(macroName) initializes a property's storage, and @\(wrapper) owns storage of its own. Write '@\(wrapper) var \(Self.name(of: variableDecl) ?? "property") = Zerk<Key>.inject()', which hands the wrapper the resolved value.")
                return nil
            }

            // Nothing encloses the declaration. Two very different things look
            // like this, and only one of them is a global.
            if context.lexicalContext.isEmpty {
                // `@Observable` rewrites a stored property into a computed one
                // and copies its attributes — this one included — onto the
                // backing storage it generates. That copy expands in a buffer of
                // its own, so it arrives with no lexical context and was read as
                // file scope. It is not, and the developer never wrote it.
                //
                // The copy always carries `@ObservationIgnored`, which is what
                // separates it from a real global here: nothing at file scope
                // has any reason to.
                if isObservationIgnored {
                    context.zerkError(attribute, Self.observedPropertyMessage(macroName))
                    return nil
                }
                context.zerkError(attribute, "\(macroName) resolves while its enclosing value is being initialized, and a global has no such moment. Write 'let \(Self.name(of: variableDecl) ?? "property") = Zerk<Key>.inject()', or use @InjectedDynamically to resolve on each access.")
                return nil
            }

            // The same property, one expansion earlier, where it is still the
            // developer's own declaration inside their own type. Refusing here
            // is what keeps the compiler from reporting "init accessor cannot
            // refer to property" against an expansion nobody wrote — and the
            // property that *is* `@ObservationIgnored` is the supported
            // spelling, so it passes.
            if !isObservationIgnored,
               context.lexicalContext.contains(where: \.declaresObservable) {
                context.zerkError(attribute, Self.observedPropertyMessage(macroName))
                return nil
            }
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
        // A generic argument names the key outright, which is what lets the
        // property be declared as something the key merely satisfies —
        // `@Injected<LiveService> var s: Serving`. Without one, the key is the
        // declared type with a layer of Optional removed. Compatibility is left
        // to the compiler: the generated peer assigns one to the other, so a
        // mismatch is rejected there, with the two real types named.
        // Read structurally, not from the text: `unwrappedOptional` handles
        // `Foo?`, `Foo!` and `Optional<Foo>` from the syntax, which is the same
        // helper the collector uses — so the macro and the plugin can never
        // disagree about what a property's key is.
        let injectedType = info.genericArguments.first?.trimmedDescription
            ?? (typeAnnotation.type.unwrappedOptional ?? typeAnnotation.type).trimmedDescription

        // A key path names a member outright, so it replaces the `inject()`
        // call rather than adding arguments to it.
        let expression = info.keyPathMember.map { "Zerk<\(injectedType)>\($0)" }
            ?? Self.buildInjectedExpression(
                injectedType: injectedType,
                arguments: info.callArguments)

        self.init(
            propertyName: identifier.identifier.text,
            backingName: "_$zerk_injection_\(identifier.identifier.text)",
            declaredType: declaredType,
            injectedType: injectedType,
            expression: expression)
    }

    /// The declared name, for a message that can name it. `nil` for the shapes
    /// rejected further down, which have no single identifier to quote.
    private static func name(of variable: VariableDeclSyntax) -> String? {
        guard variable.bindings.count == 1 else { return nil }
        return variable.bindings.first?
            .pattern.as(IdentifierPatternSyntax.self)?
            .identifier.text
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

    /// Builds `Zerk<Key>.inject()`, forwarding any attribute arguments verbatim.
    private static func buildInjectedExpression(injectedType: String,
                                                arguments: [LabeledExprSyntax]) -> String {
        let target = "Zerk<\(injectedType)>.inject"
        guard !arguments.isEmpty else {
            return "\(target)()"
        }

        // The trailing comma is part of a `LabeledExprSyntax`, so rendering the
        // node whole and joining with ", " doubles every separator — `a: 1,,
        // b: "x"`. Invisible until an attribute carries two arguments, which is
        // why it survived: every `@Injected(...)` seen so far had one.
        let argumentList = arguments
            .map { $0.with(\.trailingComma, nil).trimmedDescription }
            .joined(separator: ", ")
        return "\(target)(\(argumentList))"
    }


}
