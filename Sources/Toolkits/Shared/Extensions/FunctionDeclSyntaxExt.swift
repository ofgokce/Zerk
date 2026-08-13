//
//  FunctionDeclSyntaxExt.swift
//  Zerk
//

import SwiftSyntax

public extension FunctionDeclSyntax {
    /// The `Zerk` expression an `@ImportedInjectable` body names, or `nil` when
    /// the declaration has no body.
    ///
    /// The body must be exactly one expression naming a `Zerk` member —
    /// `Zerk<Session>.staging` or `Zerk.session(…)` — because Zerk inlines it at
    /// every use site rather than calling the function. Anything else returns
    /// `nil`, and the macro reports the malformed body against the
    /// declaration.
    ///
    /// Only the *callee* is kept: arguments are re-emitted from the declared
    /// parameters, since a bubbled parameter may be renamed on its way into the
    /// consuming signature.
    var importedResolutionIsProperty: Bool {
        guard let statements = body?.statements, statements.count == 1,
              case .expr(let expression) = statements.first?.item else {
            return false
        }
        return expression.as(FunctionCallExprSyntax.self) == nil
    }

    var importedResolutionCallee: String? {
        guard let statements = body?.statements, statements.count == 1,
              case .expr(let expression) = statements.first?.item else {
            return nil
        }

        let callee: ExprSyntax
        if let call = expression.as(FunctionCallExprSyntax.self) {
            callee = call.calledExpression
        } else {
            callee = expression
        }

        let text = callee.trimmedDescription
        guard text == "Zerk" || text.hasPrefix("Zerk.") || text.hasPrefix("Zerk<") else {
            return nil
        }
        return text
    }
}
