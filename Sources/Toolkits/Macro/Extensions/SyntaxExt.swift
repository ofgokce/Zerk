//
//  SyntaxExt.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 28.07.2026.
//

import SwiftSyntax

public extension Syntax {
    /// The name of the nearest enclosing type declaration, or `nil` at file
    /// scope. Used to tell a top-level `@InjectableValue` from one nested in
    /// a type, which must additionally be `static`.
    var enclosingTypeName: String? {
        var current = parent
        while let node = current {
            if let classDecl = node.as(ClassDeclSyntax.self) {
                return classDecl.name.text
            }
            if let structDecl = node.as(StructDeclSyntax.self) {
                return structDecl.name.text
            }
            if let enumDecl = node.as(EnumDeclSyntax.self) {
                return enumDecl.name.text
            }
            if let actorDecl = node.as(ActorDeclSyntax.self) {
                return actorDecl.name.text
            }
            current = node.parent
        }
        return nil
    }
}
