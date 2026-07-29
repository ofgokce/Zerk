//
//  AccessRank.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//
import SwiftSyntax

/// Swift's access levels, ordered so they can be compared.
///
/// A generated overload's visibility is `min(enclosing type, member)` — an
/// extension member cannot usefully be more visible than the type it extends,
/// nor than the member it overloads. Only `>= .public` matters downstream.
enum AccessRank: String, Comparable, CaseIterable {
    case `private` = "private"
    case `fileprivate` = "fileprivate"
    case `internal` = "internal"
    case `public` = "public"
    case `open` = "open"
    
    /// Backs `Comparable`. The raw values are the Swift keywords, so ordering
    /// has to be stated separately rather than derived from them.
    var intValue: Int {
        switch self {
        case .private: return 0
        case .fileprivate: return 1
        case .internal: return 2
        case .public: return 3
        case .open: return 4
        }
    }
    
    static func < (lhs: AccessRank, rhs: AccessRank) -> Bool {
        lhs.intValue < rhs.intValue
    }
}
