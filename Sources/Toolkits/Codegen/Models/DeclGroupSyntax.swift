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
}
