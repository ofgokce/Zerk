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

    /// The same keys with `any` left as written, for the spellings that end up
    /// in the generated file. See ``TypeSyntax/displayTypeKey``.
    var genericArgumentDisplayKeys: [String] {
        genericArgumentTypes.map(\.displayTypeKey)
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

    /// The attribute's `primary:` argument.
    var primaryArgument: LiteralBoolArgument {
        boolArgument(labeled: "primary")
    }

    /// The attribute's `public:` argument — how `@Injectable` and
    /// `@InjectableValues` ask for the generated members to be `public`.
    var publicArgument: LiteralBoolArgument {
        boolArgument(labeled: "public")
    }

    /// Reads a `Bool` argument by label.
    ///
    /// Zerk reads syntax and never evaluates it, so only a `true`/`false`
    /// literal can be honoured — `primary: isDebug` has no readable value.
    /// `nonLiteral` exists so that case is reported rather than silently
    /// treated as `false`.
    func boolArgument(labeled label: String) -> LiteralBoolArgument {
        for argument in labeledArguments where argument.label?.text == label {
            guard let literal = argument.expression.as(BooleanLiteralExprSyntax.self) else {
                return .nonLiteral
            }
            return .literal(literal.literal.tokenKind == .keyword(.true))
        }
        return .absent
    }

    /// Whether the attribute carries a positional argument, i.e. the
    /// `ValueInjectionMethod` in `@Injectable(.referenced)`.
    var hasPositionalArgument: Bool {
        labeledArguments.contains { $0.label == nil }
    }
}

/// The three states a `Bool` attribute argument can be in. See
/// ``AttributeSyntax/boolArgument(labeled:)``.
///
/// `absent` is distinct from `literal(false)` on purpose: an
/// `@InjectableValues(public: true)` sweep is overridden by a member that says
/// `public: false`, but not by one that says nothing at all.
public enum LiteralBoolArgument: Equatable {
    case absent
    case literal(Bool)
    case nonLiteral

    /// The claimed value, defaulting to `false` for anything unreadable. The
    /// unreadable case is reported separately, so this only decides what the
    /// generated code does while the build is already failing.
    public var isTrue: Bool {
        self == .literal(true)
    }
}
