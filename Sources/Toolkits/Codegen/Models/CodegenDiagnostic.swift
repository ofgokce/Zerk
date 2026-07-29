//
//  CodegenDiagnostic.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

/// One problem found while generating.
///
/// Diagnostics are collected and emitted together rather than thrown at the
/// first failure, so a single build reports everything that is wrong.
struct CodegenDiagnostic {
    let severity: DiagnosticSeverity
    let message: String
    let location: AttributeLocation
}
