//
//  ZerkAliasMacro.swift
//  Zerk
//

import MacroToolkit
import SharedToolkit
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Validates `@ZerkAlias` and expands to nothing.
///
/// The equivalence it declares is module-wide, so the build plugin is what acts
/// on it — as with every other Zerk marker. All this macro can decide from one
/// declaration is that the attribute is on something that *is* a typealias, and
/// that the alias is not generic.
public struct ZerkAliasMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax,
                                 providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let alias = declaration.as(TypeAliasDeclSyntax.self) else {
            context.zerkError(
                node,
                "@ZerkAlias can only be applied to a typealias."
            )
            return []
        }

        if let parameters = alias.genericParameterClause?.parameters, !parameters.isEmpty {
            context.zerkError(
                node,
                "@ZerkAlias does not support generic typealiases. '\(alias.name.text)' has type parameters, and Zerk matches keys by spelling rather than resolving them. Alias a concrete instantiation instead, e.g. typealias IntPair = \(alias.name.text)<Int>."
            )
        }

        return []
    }
}

/// Expands `#ZerkAlias<A, B, C>` into a compile-time proof that the listed types
/// really are interchangeable.
///
/// The plugin takes the listing on trust when it builds the key graph, so the
/// generated code has to be what checks it — otherwise a wrong `#ZerkAlias`
/// would silently merge two unrelated keys and misroute every dependency of
/// both.
///
/// Each pair goes through a generic function taking two `T.Type` arguments. That
/// position is invariant, which is the point: a coercion like `A.self as B.Type`
/// accepts a subclass for its superclass, and `(nil as A?) as B?` does too, so
/// either would quietly certify `Sub` and `Base` as the same key. It also avoids
/// the existential-metatype trap — `A.self` is `(any A).Type` while `B.Type`
/// reads as `any B.Type`, so the direct coercion does not even compile when the
/// types are protocols, which is the common case for an injection key.
public struct ZerkAliasDeclarationMacro: DeclarationMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        let types = node.genericArgumentClause?.arguments.map(\.argument) ?? []

        // The trailing `()` is not optional. Written bare, `#ZerkAlias<A, B>`
        // parses as a macro expansion *expression* named `ZerkAlias` followed by
        // loose `<`/`>` tokens, and the generic clause never reaches the macro —
        // so the empty argument list is what makes the types visible here.
        guard types.count >= 2 else {
            context.zerkError(
                Syntax(node),
                "#ZerkAlias needs at least two types to relate, written as #ZerkAlias<A, B>() — the trailing '()' is required, without it Swift does not pass the types to the macro."
            )
            return []
        }

        // Compared as canonical keys, so `[String]` and `Array<String>` count as
        // one entry — they are already the same key, and relating them would be
        // a no-op the author probably did not intend.
        var seen: [String: TypeSyntax] = [:]
        for type in types {
            let key = type.normalizedTypeKey
            if let first = seen[key] {
                let spellings = first.trimmedDescription == type.trimmedDescription
                    ? "'\(type.trimmedDescription)' twice"
                    : "'\(first.trimmedDescription)' and '\(type.trimmedDescription)', which are already one key"
                context.zerkError(
                    Syntax(node),
                    "#ZerkAlias lists \(spellings). Every listed type must be a distinct key."
                )
                return []
            }
            seen[key] = type
        }

        // Every unordered pair once: the helper's two parameters share one type
        // variable, so the relation it checks is symmetric and `(B, A)` would
        // restate `(A, B)`.
        var checks: [String] = []
        for (offset, lhs) in types.enumerated() {
            for rhs in types.dropFirst(offset + 1) {
                checks.append(
                    "    interchangeable(\(lhs.trimmedDescription).self, \(rhs.trimmedDescription).self)"
                )
            }
        }

        // A unique name per expansion, so several #ZerkAlias in one file cannot
        // collide.
        let functionName = context.makeUniqueName("zerk_alias_check")

        return [
            """
            private func \(functionName)() {
                func interchangeable<T>(_: T.Type, _: T.Type) {}
            \(raw: checks.joined(separator: "\n"))
            }
            """
        ]
    }
}
