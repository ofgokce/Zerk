//
//  MacroExpansionContextExt.swift
//  Zerk
//

import SwiftSyntax
import SwiftSyntaxMacros

public extension MacroExpansionContext {
    /// Whether this expansion is for the **first** of a declaration's repeated
    /// Zerk attributes.
    ///
    /// A declaration may carry several — one per key — and an attached macro
    /// expands once per attribute. Checks that look at all of them together, or
    /// at the declaration as a whole, have to run once or every error is
    /// reported once per attribute.
    ///
    /// Compared by **source location**, not by `id`. The attribute handed to a
    /// macro is a detached copy, so `node.id` never equals the one found on the
    /// declaration: a `first.id == node.id` guard is not "run once", it is "never
    /// run", and it silently disabled every check behind it. Verified by
    /// instrumenting the comparison — it is `false` even for a declaration
    /// carrying exactly one attribute.
    ///
    /// Falls back to `true` when a location is unavailable, so a check that
    /// cannot be positioned still runs rather than vanishing.
    func isFirstAttribute(_ node: AttributeSyntax,
                          among attributes: [AttributeSyntax]) -> Bool {
        guard let first = attributes.first else {
            return false
        }
        guard let nodeLocation = location(of: node),
              let firstLocation = location(of: first) else {
            return true
        }
        return nodeLocation.line.description == firstLocation.line.description
            && nodeLocation.column.description == firstLocation.column.description
            && nodeLocation.file.description == firstLocation.file.description
    }
}
