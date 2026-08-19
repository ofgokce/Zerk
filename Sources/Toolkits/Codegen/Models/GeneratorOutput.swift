//
//  GeneratorOutput.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

/// The result of a generation run: the file to write, everything worth
/// reporting about it, and the facts `CodeGenerator` gates on afterwards.
struct GeneratorOutput {
    let output: String
    let diagnostics: [CodegenDiagnostic]
    /// Whether the generated source contains at least one same-domain isolated
    /// default argument — the only construct whose legality depends on SE-0411,
    /// and so the only one a Swift 5 language mode target can reject.
    var usesIsolatedDefaultArguments: Bool = false
}
