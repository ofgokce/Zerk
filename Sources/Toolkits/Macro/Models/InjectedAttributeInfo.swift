//
//  InjectedAttributeInfo.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 28.07.2026.
//

import SharedToolkit
import SwiftSyntax

/// What was written inside an `@Injected(...)` attribute.
///
/// Three shapes, told apart by syntax:
///
/// - `@Injected` — resolve the key's primary through `inject()`.
/// - `@Injected(seed: 100)` — arguments forwarded *into* `inject(seed:)`.
/// - `@Injected(\.cached)` — a key path naming one specific `Zerk<Key>` member
///   instead of the primary.
///
/// The generic argument, where present, restates the property's own type
/// (`@Injected<Service>`) and is checked against it.
public struct InjectedAttributeInfo {

    public let genericArguments: [TypeSyntax]
    public let callArguments: [LabeledExprSyntax]
    /// The member named by a key-path argument, rendered with its leading dot
    /// (`.cached`), or `nil` when no key path was written.
    ///
    /// Only the components are kept: the root is whatever `Zerk<Key>.Type` the
    /// property's type implies, which the macro reconstructs itself.
    public let keyPathMember: String?

    init(genericArguments: [TypeSyntax],
         callArguments: [LabeledExprSyntax],
         keyPathMember: String?) {
        self.genericArguments = genericArguments
        self.callArguments = callArguments
        self.keyPathMember = keyPathMember
    }

    public init(from attribute: AttributeSyntax) {
        let arguments = attribute.labeledArguments

        if arguments.count == 1,
           arguments[0].label == nil,
           let keyPath = arguments[0].expression.as(KeyPathExprSyntax.self) {
            self.init(
                genericArguments: attribute.genericArgumentTypes,
                callArguments: [],
                keyPathMember: keyPath.components.map(\.trimmedDescription).joined())
            return
        }

        self.init(
            genericArguments: attribute.genericArgumentTypes,
            callArguments: arguments,
            keyPathMember: nil)
    }
}
