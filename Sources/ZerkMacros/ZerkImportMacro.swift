//
//  ZerkImportMacro.swift
//  Zerk
//

import SharedToolkit
import SwiftSyntax
import SwiftSyntaxMacros

/// Validates `#ZerkImport` and expands to nothing.
///
/// Which modules the generated file imports is a module-wide fact assembled from
/// every occurrence, so the build plugin acts on it. All this macro can decide
/// from one expansion is that the arguments are readable: the plugin reads them
/// out of source, so anything it cannot read from syntax has to be refused here
/// rather than silently dropped.
public struct ZerkImportMacro: DeclarationMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        let arguments = Array(node.arguments)

        guard !arguments.isEmpty else {
            context.zerkError(
                Syntax(node),
                "#ZerkImport needs at least one module name, e.g. #ZerkImport(module: \"Foundation\")."
            )
            return []
        }

        for argument in arguments where argument.moduleNameLiteral == nil {
            context.zerkError(
                Syntax(node),
                "#ZerkImport takes plain string literals. Zerk reads these from source and cannot evaluate '\(argument.expression.trimmedDescription)'."
            )
        }

        return []
    }
}
