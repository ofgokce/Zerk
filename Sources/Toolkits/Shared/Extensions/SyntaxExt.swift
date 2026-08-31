//
//  SyntaxExt.swift
//  Zerk
//

import SwiftSyntax

public extension Syntax {
    /// Whether this lexical-context frame is a type carrying `@Observable`.
    ///
    /// Read to tell an observed property from an ordinary one *before* an init
    /// accessor is generated for it. The four declaration kinds are spelled out
    /// rather than reached through a common protocol because only these can
    /// carry the attribute, and an `extension` — which cannot — must not match.
    var declaresObservable: Bool {
        let attributes: AttributeListSyntax?
        switch self.as(DeclSyntax.self)?.as(DeclSyntaxEnum.self) {
        case .classDecl(let decl): attributes = decl.attributes
        case .structDecl(let decl): attributes = decl.attributes
        case .actorDecl(let decl): attributes = decl.attributes
        case .enumDecl(let decl): attributes = decl.attributes
        default: attributes = nil
        }
        return attributes?.hasAttribute(named: "Observable") ?? false
    }
}
