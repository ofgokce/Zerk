//
//  InterjectMacro.swift
//  Zerk
//

import MacroToolkit
import SharedToolkit
import SwiftSyntax
import SwiftSyntaxMacros

/// Expands `#Interject` into a registration against the scope in force.
///
/// Two shapes come out, and which one depends on whether the key was written:
///
/// ```swift
/// #Interject<Loading>(with: Mock())   ->  Zerk<Loading>._$interject { Mock() }
/// #Interject(\.live, with: Mock())    ->  _$zerkInterject(\.live) { Mock() }
/// ```
///
/// The second cannot name `Zerk<Loading>`, because a macro sees only syntax and
/// never learns what the key path's root was inferred to be. Expanding to the
/// free function hands that back to the type checker, which solved it to begin
/// with.
public struct InterjectMacro: ExpressionMacro {

    public static func expansion(of node: some FreestandingMacroExpansionSyntax,
                                 in context: some MacroExpansionContext) throws -> ExprSyntax {
        let key: String? = node.genericArgumentClause?.arguments.first.flatMap { argument in
            guard case .type(let type) = argument.argument else {
                return nil
            }
            return type.trimmedDescription
        }
        let arguments = Array(node.arguments)

        // The key path, when one was written: the sole unlabelled argument that
        // is a key path literal.
        let keyPath = arguments.first {
            $0.label == nil && $0.expression.is(KeyPathExprSyntax.self)
        }?.expression

        guard key != nil || keyPath != nil else {
            context.zerkError(
                node,
                "#Interject needs the key it stands in for. Name a member — '#Interject(\\.live, with: …)' — or state the key for a blanket interjection — '#Interject<Loading>(with: …)'."
            )
            return "()"
        }

        guard let body = try body(of: node, arguments: arguments, in: context) else {
            return "()"
        }

        let receiver = key.map { "Zerk<\($0)>._$interject" } ?? "_$zerkInterject"

        guard let keyPath else {
            return "\(raw: receiver)(\(raw: body))"
        }
        // Trailing position rather than a second argument, which reads better
        // and keeps the key path last in the emitted call.
        return "\(raw: receiver)(\(raw: keyPath.trimmedDescription)) \(raw: body)"
    }

    /// The closure that produces the double, however it was written.
    ///
    /// `with:` is an autoclosure at the declaration, so what arrives here is the
    /// bare expression and wrapping it is what preserves the laziness the
    /// signature promises — the double is rebuilt per resolution, not captured
    /// once.
    private static func body(of node: some FreestandingMacroExpansionSyntax,
                             arguments: [LabeledExprSyntax],
                             in context: some MacroExpansionContext) throws -> String? {
        if let value = arguments.first(where: { $0.label?.text == "with" })?.expression {
            return "{ \(value.trimmedDescription) }"
        }
        if let trailing = node.trailingClosure {
            return trailing.trimmedDescription
        }
        // The closure form written in parentheses rather than trailing.
        if let closure = arguments.last(where: {
            $0.label == nil && $0.expression.is(ClosureExprSyntax.self)
        })?.expression {
            return closure.trimmedDescription
        }

        context.zerkError(
            node,
            "#Interject needs the double to stand in: pass it as 'with:', or write it as a trailing closure."
        )
        return nil
    }
}
