//
//  DeclSyntaxProtocolExt.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 28.07.2026.
//

import SwiftSyntax

public extension DeclSyntaxProtocol {
    /// The declaration's modifier list, for the kinds Zerk inspects.
    ///
    /// SwiftSyntax exposes no common protocol carrying `modifiers`, so the
    /// cases are enumerated by hand; anything unlisted yields `nil`.
    var modifiers: DeclModifierListSyntax? {
        if let decl = self.as(ClassDeclSyntax.self) { return decl.modifiers }
        if let decl = self.as(StructDeclSyntax.self) { return decl.modifiers }
        if let decl = self.as(EnumDeclSyntax.self) { return decl.modifiers }
        if let decl = self.as(ActorDeclSyntax.self) { return decl.modifiers }
        if let decl = self.as(FunctionDeclSyntax.self) { return decl.modifiers }
        if let decl = self.as(InitializerDeclSyntax.self) { return decl.modifiers }
        if let decl = self.as(VariableDeclSyntax.self) { return decl.modifiers }
        return nil
    }
}
