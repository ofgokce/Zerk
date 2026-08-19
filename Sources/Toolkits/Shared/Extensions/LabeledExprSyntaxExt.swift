//
//  LabeledExprSyntaxExt.swift
//  Zerk
//

import SwiftSyntax

public extension LabeledExprSyntax {
    /// The module name this argument spells, or `nil` when it is not a plain
    /// string literal.
    ///
    /// Interpolation and multi-segment literals are rejected along with
    /// everything else: the build plugin reads these out of source and never
    /// evaluates them, so a name it cannot see literally is a name it cannot
    /// import. Shared by the macro, which reports the refusal, and the
    /// collector, which gathers what survived.
    var moduleNameLiteral: String? {
        guard let literal = expression.as(StringLiteralExprSyntax.self),
              literal.segments.count == 1,
              case .stringSegment(let segment)? = literal.segments.first else {
            return nil
        }
        return segment.content.text
    }
}
