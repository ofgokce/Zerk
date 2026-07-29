//
//  AttributeSyntaxExt.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 28.07.2026.
//

import SwiftSyntax

public extension AttributeSyntax {
    /// The attribute's bare name, with any module qualification dropped, so
    /// `@Zerk.Injectable` and `@Injectable` compare equal.
    var name: String {
        if let identifier = attributeName.as(IdentifierTypeSyntax.self) {
            return identifier.name.text
        }
        if let member = attributeName.as(MemberTypeSyntax.self) {
            return member.name.text
        }
        return attributeName.trimmedDescription
    }

    /// The types written inside `@Attribute<A, B>` — how every Zerk attribute
    /// carries the key it applies to. Empty when unparameterized.
    var genericArgumentTypes: [TypeSyntax] {
        guard let identifier = attributeName.as(IdentifierTypeSyntax.self),
              let clause = identifier.genericArgumentClause else {
            return []
        }

        return clause.arguments.map(\.argument)
    }

    var genericArgumentKeys: [String] {
        genericArgumentTypes.map(\.normalizedTypeKey)
    }

    /// The call-style arguments of `@Attribute(...)`, as used by
    /// `@Injected(Zerk<T>.custom)`. Empty for attributes written without
    /// parentheses.
    var labeledArguments: [LabeledExprSyntax] {
        guard let arguments else {
            return []
        }

        switch arguments {
        case .argumentList(let list):
            return Array(list)
        default:
            return []
        }
    }
}
