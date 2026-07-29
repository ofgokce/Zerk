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
/// Two shapes are possible and they mean opposite things:
///
/// - `@Injected(Zerk<T>.custom)` — one unlabeled expression naming a `Zerk`
///   member, which *replaces* resolution outright.
/// - `@Injected(id: 3)` — arguments forwarded *into* the resolved provider.
///
/// They are told apart by the expression starting with `Zerk`. That is a
/// syntactic test, so an expression reaching a `Zerk` member by any other
/// spelling is read as call arguments instead.
public struct InjectedAttributeInfo {
    
    public let genericArguments: [TypeSyntax]
    public let explicitExpression: String?
    public let callArguments: [LabeledExprSyntax]
    
    init(genericArguments: [TypeSyntax],
         explicitExpression: String?,
         callArguments: [LabeledExprSyntax]) {
        self.genericArguments = genericArguments
        self.explicitExpression = explicitExpression
        self.callArguments = callArguments
    }

    public init(from attribute: AttributeSyntax) {
        
        let genericArguments = attribute.genericArgumentTypes
        let arguments = attribute.labeledArguments

        if arguments.count == 1, arguments[0].label == nil {
            let explicit = arguments[0].expression.trimmedDescription
            if explicit.hasPrefix("Zerk") {
                self.init(
                    genericArguments: genericArguments,
                    explicitExpression: explicit,
                    callArguments: [])
                return
            }
        }

        self.init(
            genericArguments: genericArguments,
            explicitExpression: nil,
            callArguments: arguments)
    }
}
