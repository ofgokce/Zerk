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

    public var inheritanceClause: InheritanceClauseSyntax? {
        switch self {
        case .class(let decl):
            return decl.inheritanceClause
        case .struct(let decl):
            return decl.inheritanceClause
        case .enum(let decl):
            return decl.inheritanceClause
        case .actor(let decl):
            return decl.inheritanceClause
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

    /// Whether `@injected` members may be generated for this type.
    ///
    /// Excludes enums: the generated overload of an initializer would have to
    /// assign to `self` from an extension, which enums do not permit.
    public var isMemberInjectionSupported: Bool {
        switch self {
        case .enum:
            return false
        case .class, .struct, .actor:
            return true
        }
    }

    /// Whether the declaration *itself* lists `typeKey` as a supertype.
    ///
    /// Only the inheritance clause written on the declaration is visible here.
    /// A conformance added in an extension, inherited transitively, or declared
    /// in another module reads as absent — which is why `@Injectable<Key>`
    /// requires the conformance to be spelled on the type.
    public func inheritsOrConforms(to typeKey: String) -> Bool {
        guard let clause = inheritanceClause else {
            return false
        }

        for inherited in clause.inheritedTypes
        where inherited.type.normalizedTypeKey == typeKey {
            return true
        }
        
        return false
    }
}
