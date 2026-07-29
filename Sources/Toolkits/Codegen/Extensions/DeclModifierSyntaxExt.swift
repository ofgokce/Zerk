//
//  DeclModifierSyntaxExt.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

import SwiftSyntax

extension DeclModifierSyntax {
    var isPublic: Bool {
        name.text == "public"
        || name.text == "open"
    }
    /// The access level this modifier declares, or `nil` if it declares none.
    ///
    /// The `detail == nil` guard skips `private(set)` and friends: those
    /// restrict only the setter, so they must not lower the declaration's
    /// effective access.
    var accessRank: AccessRank? {
        if detail == nil, let accessRank = AccessRank(rawValue: name.text) {
            return accessRank
        }
        return nil
    }
}
