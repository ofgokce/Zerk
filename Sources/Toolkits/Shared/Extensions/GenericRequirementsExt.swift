//
//  GenericRequirementsExt.swift
//  Zerk
//

import SwiftSyntax

/// Reads the requirements a provider places on its *own* generic parameters, in
/// the form the generated member emits them.
///
/// Both halves of a generic declaration say the same kind of thing — `<Z: Numeric>`
/// is sugar for `where Z: Numeric` — so they are read into one list of `where`
/// requirements. The member already carries a `where` clause when its key is
/// generic, and requirements join with a comma.
///
/// Text is taken as written. Zerk reads syntax and cannot resolve a constraint,
/// so anything else would be a guess: a requirement naming an associated type
/// (`Z.Element == A`) or a type from another module has to arrive at the
/// generated file spelled exactly as the developer spelled it.
public protocol GenericProviding {
    var genericParameterClause: GenericParameterClauseSyntax? { get }
    var genericWhereClauseSyntax: GenericWhereClauseSyntax? { get }
}

public extension GenericProviding {
    /// The parameter names alone — `["Z"]` for `init<Z: Numeric>`.
    var declaredGenericParameters: [String] {
        genericParameterClause?.parameters.map { $0.name.text } ?? []
    }

    /// Every requirement, as `where`-clause text: an inheritance clause becomes
    /// `"Z: Numeric"`, and a written `where` requirement is carried verbatim.
    var declaredGenericRequirements: [String] {
        var requirements: [String] = []

        for parameter in genericParameterClause?.parameters ?? [] {
            guard let inherited = parameter.inheritedType else {
                continue
            }
            requirements.append("\(parameter.name.text): \(inherited.trimmedDescription)")
        }

        for requirement in genericWhereClauseSyntax?.requirements ?? [] {
            requirements.append(
                requirement.requirement.trimmedDescription
                    .trimmingCharacters(in: .whitespaces)
            )
        }

        return requirements
    }
}

extension InitializerDeclSyntax: GenericProviding {
    public var genericWhereClauseSyntax: GenericWhereClauseSyntax? { genericWhereClause }
}

extension FunctionDeclSyntax: GenericProviding {
    public var genericWhereClauseSyntax: GenericWhereClauseSyntax? { genericWhereClause }
}
