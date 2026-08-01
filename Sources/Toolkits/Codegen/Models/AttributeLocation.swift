//
//  AttributeLocation.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

/// A position in the *developer's* source.
///
/// Every diagnostic carries one so the build system points at the declaration
/// that caused the problem rather than at generated code nobody wrote.
struct AttributeLocation: Comparable {
    let filePath: String
    let line: Int
    let column: Int

    /// Source order, so that "the *second* provider is the problem" picks the
    /// same declaration on every build. Records reach the resolver grouped by
    /// type and by key — both dictionaries — so without an explicit ordering
    /// the choice would drift between runs.
    static func < (lhs: AttributeLocation, rhs: AttributeLocation) -> Bool {
        (lhs.filePath, lhs.line, lhs.column) < (rhs.filePath, rhs.line, rhs.column)
    }
}
