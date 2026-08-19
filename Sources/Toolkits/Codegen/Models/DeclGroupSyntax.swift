//
//  DeclGroupSyntax.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

import SwiftSyntax

extension DeclGroupSyntax {
    /// The declared type's name, for the four kinds Zerk can register.
    ///
    /// Returns `"Unknown"` for anything else (an `extension`, say) rather than
    /// failing: callers only reach this after confirming the declaration is
    /// injectable, so an unnamed group is a placeholder, not an error path.
    var declaredName: String {
        if let node = self.as(ClassDeclSyntax.self) {
            return node.name.text
        }
        if let node = self.as(StructDeclSyntax.self) {
            return node.name.text
        }
        if let node = self.as(EnumDeclSyntax.self) {
            return node.name.text
        }
        if let node = self.as(ActorDeclSyntax.self) {
            return node.name.text
        }
        return "Unknown"
    }

    /// The declared type's generic parameters, for the same four kinds.
    ///
    /// `DeclGroupSyntax` exposes `genericWhereClause` but not the parameter
    /// clause, so a caller holding `some DeclGroupSyntax` cannot ask whether the
    /// type is generic without switching on the concrete kind. This is that
    /// switch, kept next to ``declaredName`` because they are always wanted
    /// together: a type's key is its name plus these.
    var declaredGenericParameters: GenericParameterClauseSyntax? {
        if let node = self.as(ClassDeclSyntax.self) {
            return node.genericParameterClause
        }
        if let node = self.as(StructDeclSyntax.self) {
            return node.genericParameterClause
        }
        if let node = self.as(EnumDeclSyntax.self) {
            return node.genericParameterClause
        }
        if let node = self.as(ActorDeclSyntax.self) {
            return node.genericParameterClause
        }
        return nil
    }

    /// The names of the declared type's generic parameters, in order.
    var declaredGenericParameterNames: [String] {
        declaredGenericParameters?.parameters.map { $0.name.text } ?? []
    }
}
