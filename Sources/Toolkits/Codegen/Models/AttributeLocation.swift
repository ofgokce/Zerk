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
struct AttributeLocation {
    let filePath: String
    let line: Int
    let column: Int
}
