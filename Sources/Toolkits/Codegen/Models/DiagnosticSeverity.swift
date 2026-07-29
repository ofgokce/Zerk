//
//  DiagnosticSeverity.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

/// An `error` fails the build and suppresses output; a `warning` is reported
/// and the generated file is still written.
enum DiagnosticSeverity {
    case error
    case warning
}
