//
//  DeclModifierListSyntaxExt.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 28.07.2026.
//

import SwiftSyntax

public extension DeclModifierListSyntax {
    var isStatic: Bool {
        contains(where: \.isStatic)
    }

    var isNonisolated: Bool {
        contains(where: \.isNonisolated)
    }

    func hasModifier(named name: String) -> Bool {
        contains { modifier in
            modifier.name.text == name
        }
    }
}
