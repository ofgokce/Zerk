//
//  DeclModifierListSyntaxExt.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

import SwiftSyntax

extension DeclModifierListSyntax {
    var isPublic: Bool {
        contains(where: \.isPublic)
    }
    /// The declared access level, falling back to `internal` — Swift's own
    /// default when none is written.
    var accessRank: AccessRank {
        compactMap(\.accessRank).first ?? .internal
    }
}
