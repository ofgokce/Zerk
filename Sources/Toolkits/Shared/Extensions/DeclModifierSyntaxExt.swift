//
//  DeclModifierSyntaxExt.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 28.07.2026.
//

import SwiftSyntax

public extension DeclModifierSyntax {
    /// Counts `class` as static: a `class func` is called on the type, which
    /// is all a provider needs in order to run without an instance.
    var isStatic: Bool {
        name.text == "static"
        || name.text == "class"
    }

    var isNonisolated: Bool {
        name.text == "nonisolated"
    }
}
