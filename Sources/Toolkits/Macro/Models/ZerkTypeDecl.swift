//
//  ZerkTypeDecl.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 28.07.2026.
//

import SharedToolkit
import SwiftSyntax

/// The four type declarations Zerk can register, behind one interface.
///
/// SwiftSyntax gives class/struct/enum/actor no common protocol exposing a
/// name, attributes, inheritance clause, and members, so this enum supplies
/// one. Its failable initializer doubles as the "is this registrable?" test.
public enum ZerkTypeDecl {
    
    case `class`(ClassDeclSyntax)
    case `struct`(StructDeclSyntax)
    case `enum`(EnumDeclSyntax)
    case actor(ActorDeclSyntax)

    public init?(_ declaration: some DeclSyntaxProtocol) {
        if let decl = declaration.as(ClassDeclSyntax.self) {
            self = .class(decl)
        } else if let decl = declaration.as(StructDeclSyntax.self) {
            self = .struct(decl)
        } else if let decl = declaration.as(EnumDeclSyntax.self) {
            self = .enum(decl)
        } else if let decl = declaration.as(ActorDeclSyntax.self) {
            self = .actor(decl)
        } else {
            return nil
        }
    }

    public var nameText: String {
        switch self {
        case .class(let decl):
            return decl.name.text
        case .struct(let decl):
            return decl.name.text
        case .enum(let decl):
            return decl.name.text
        case .actor(let decl):
            return decl.name.text
        }
    }

    /// The declaration's generic parameters, in order, or empty when it has
    /// none. A type's Zerk key is its name plus these, so the two are always
    /// read together.
    public var genericParameterNames: [String] {
        let clause: GenericParameterClauseSyntax?
        switch self {
        case .class(let decl):
            clause = decl.genericParameterClause
        case .struct(let decl):
            clause = decl.genericParameterClause
        case .enum(let decl):
            clause = decl.genericParameterClause
        case .actor(let decl):
            clause = decl.genericParameterClause
        }
        return clause?.parameters.map { $0.name.text } ?? []
    }

    public var attributes: AttributeListSyntax {
        switch self {
        case .class(let decl):
            return decl.attributes
        case .struct(let decl):
            return decl.attributes
        case .enum(let decl):
            return decl.attributes
        case .actor(let decl):
            return decl.attributes
        }
    }

    public var members: MemberBlockSyntax {
        switch self {
        case .class(let decl):
            return decl.memberBlock
        case .struct(let decl):
            return decl.memberBlock
        case .enum(let decl):
            return decl.memberBlock
        case .actor(let decl):
            return decl.memberBlock
        }
    }

}
