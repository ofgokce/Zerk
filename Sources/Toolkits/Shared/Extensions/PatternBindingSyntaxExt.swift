//
//  PatternBindingSyntaxExt.swift
//  Zerk
//

import SwiftSyntax
public extension PatternBindingSyntax {
    /// The `Zerk` expression an `@ImportedInjectableValue` getter names.
    ///
    /// A value import always states which member it means — there is no "the
    /// primary `String`" to fall back on — so unlike the function form there is
    /// nothing to synthesise and a missing or unreadable body is simply an
    /// error. The whole expression is kept, not just a callee: a value takes no
    /// arguments, so there is nothing to re-emit around it.
    ///
    /// Accepts the getter-only spellings a value can have — `{ Zerk<Key>.x }` and
    /// `{ get { Zerk<Key>.x } }` — and `= Zerk<Key>.x`, which reads the foreign
    /// member once at initialization rather than per resolution and so is
    /// refused by the macro rather than honoured here.
    var importedValueExpression: String? {
        guard let expression = soleGetterExpression else {
            return nil
        }
        let text = expression.trimmedDescription
        guard text.hasPrefix("Zerk<") || text.hasPrefix("Zerk.") else {
            return nil
        }
        return text
    }

    /// Whether the declaration reads through a getter at all. A stored binding
    /// (`= Zerk<Key>.x`) captures the foreign value once; the import has to be
    /// re-read per resolution, so the two are not interchangeable.
    var hasGetter: Bool {
        guard let accessors = accessorBlock?.accessors else {
            return false
        }
        switch accessors {
        case .getter:
            return true
        case .accessors(let list):
            return list.contains { $0.accessorSpecifier.text == "get" }
        }
    }

    /// The `async`/`throws` the getter declares, as written, or `nil` for a
    /// stored or plain computed property.
    ///
    /// Only an explicit `get` can carry them. Swift has no effectful setter
    /// (SE-0310 is read-only), so a value with effects is read-only too.
    var getterEffectSpecifiers: String? {
        guard case .accessors(let list)? = accessorBlock?.accessors else {
            return nil
        }
        return list.first { $0.accessorSpecifier.text == "get" }?
            .effectSpecifiers?.trimmedDescription
    }

    /// The **statements** to re-emit as the generated member's body, `return`
    /// included.
    ///
    /// Deliberately the getter's statements rather than the whole accessor
    /// block: `{ get async throws { … } }` re-emitted verbatim is not a body, and
    /// neither is a `get`/`set` pair. A stored binding contributes its
    /// initializer instead, which is what makes a `.copied` value recompute per
    /// resolution rather than being captured once.
    ///
    /// Statements rather than an expression because a body may have several —
    /// `try await` something, then transform it — and because the generated
    /// getter opens with the interjection guard, so Swift's implicit return for
    /// a single-expression getter no longer applies. A source body that relied
    /// on it gets an explicit `return` here.
    var valueBodyText: String? {
        if let initializer {
            return "return \(initializer.value.trimmedDescription)"
        }
        guard let accessors = accessorBlock?.accessors else {
            return nil
        }
        switch accessors {
        case .getter(let statements):
            return Self.statementText(statements)
        case .accessors(let list):
            guard let getter = list.first(where: { $0.accessorSpecifier.text == "get" }),
                  let body = getter.body else {
                return nil
            }
            return Self.statementText(body.statements)
        }
    }

    private static func statementText(_ statements: CodeBlockItemListSyntax) -> String {
        if statements.count == 1, case .expr(let expression) = statements.first?.item {
            return "return \(expression.trimmedDescription)"
        }
        return statements.trimmedDescription
    }

    private var soleGetterExpression: ExprSyntax? {
        guard let accessors = accessorBlock?.accessors else {
            return nil
        }

        let statements: CodeBlockItemListSyntax
        switch accessors {
        case .getter(let items):
            statements = items
        case .accessors(let list):
            guard list.count == 1,
                  let getter = list.first,
                  getter.accessorSpecifier.text == "get",
                  let body = getter.body else {
                return nil
            }
            statements = body.statements
        }

        guard statements.count == 1,
              case .expr(let expression) = statements.first?.item else {
            return nil
        }
        return expression
    }
}
