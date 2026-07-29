//
//  TypeSyntaxExt.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 28.07.2026.
//

import Foundation
import SwiftSyntax

public extension TypeSyntax {
    /// A type's spelling with whitespace stripped, used as its identity when
    /// matching a dependency to a provider.
    ///
    /// Purely syntactic — Zerk compares what was written. `[String]` and
    /// `Array<String>` are distinct keys here even though the compiler treats
    /// them as one type.
    var normalizedTypeKey: String {
        trimmedDescription
            .replacingOccurrences(of: " ", with: "")
    }
}
