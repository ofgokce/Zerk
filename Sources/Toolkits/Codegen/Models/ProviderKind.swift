//
//  ProviderKind.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

/// How the generated code calls a provider: `Type(...)` for an initializer,
/// or `Type.name(...)` for a static factory.
enum ProviderKind {
    case initializer
    case staticFunction(name: String)
}
