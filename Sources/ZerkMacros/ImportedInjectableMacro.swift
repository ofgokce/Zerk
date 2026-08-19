//
//  ImportedInjectableMacro.swift
//  Zerk
//

import SharedToolkit
import SwiftSyntax
import SwiftSyntaxMacros

/// Gives an `@ImportedInjectable` declaration a body, which is what checks it.
///
/// The plugin takes the declaration's *shape* on trust when it wires the key
/// into this module's graph. The body is what makes that trust verifiable: it
/// resolves the key exactly as the graph will, so an import that names a key
/// nothing exports — or gets its parameters or effects wrong — fails to compile
/// here, at the declaration, rather than somewhere downstream.
///
/// A body macro must return **non-empty** statements. Returning none is read as
/// "no body provided" and reported as `expected '{' in body of function
/// declaration`, which reads like a syntax error in the developer's source.
public struct ImportedInjectableMacro: BodyMacro {
    public static func expansion(of node: AttributeSyntax,
                                 providingBodyFor declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
                                 in context: some MacroExpansionContext) throws -> [CodeBlockItemSyntax] {
        guard let function = declaration.as(FunctionDeclSyntax.self) else {
            context.zerkError(node, "@ImportedInjectable can only be applied to a function.")
            return ["fatalError()"]
        }

        guard let returnType = function.signature.returnClause?.type,
              returnType.normalizedTypeKey != "Void" else {
            context.zerkError(
                node,
                "@ImportedInjectable must declare the type it imports as its return type."
            )
            return ["fatalError()"]
        }

        // A body that was written stays as written — it names the member to
        // resolve through, and the plugin inlines it.
        if let statements = function.body?.statements, !statements.isEmpty {
            if function.importedResolutionCallee == nil {
                context.zerkError(
                    node,
                    "@ImportedInjectable's body must be a single Zerk expression, e.g. 'Zerk<\(returnType.trimmedDescription)>.staging'. Zerk inlines it wherever the dependency is resolved, so it cannot contain other logic."
                )
            }
            return Array(statements)
        }

        // `try`/`await` mirror what the declaration states, so the synthesised
        // call is well-formed for an import declared with either.
        let specifiers = function.signature.effectSpecifiers?.trimmedDescription ?? ""
        var callPrefix = ""
        if specifiers.contains("throws") { callPrefix += "try " }
        if specifiers.contains("async") { callPrefix += "await " }

        let arguments = function.signature.parameterClause.parameters
            .map { parameter -> String in
                let name = parameter.secondName?.text ?? parameter.firstName.text
                let label = parameter.firstName.text
                return label == "_" ? name : "\(label): \(name)"
            }
            .joined(separator: ", ")

        return [
            "return \(raw: callPrefix)Zerk<\(raw: returnType.trimmedDescription)>.inject(\(raw: arguments))"
        ]
    }
}
