//
//  ZerkMacroDiagnostics.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 28.07.2026.
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// A macro diagnostic carrying Zerk's own message domain, so its errors are
/// attributable to Zerk rather than to the compiler.
public struct ZerkDiagnosticMessage: DiagnosticMessage {
    
    public let message: String
    public let diagnosticID: MessageID
    public let severity: DiagnosticSeverity

    public init(message: String,
                diagnosticID: MessageID,
                severity: DiagnosticSeverity) {
        self.message = message
        self.diagnosticID = diagnosticID
        self.severity = severity
    }
}

public extension MacroExpansionContext {
    /// Reports an error anchored at `node` — normally the attribute itself, so
    /// the message lands on the annotation the developer wrote.
    func zerkError(_ node: some SyntaxProtocol,
                   _ message: String,
                   id: String = "Zerk") {
        let diagnostic = Diagnostic(
            node: Syntax(node),
            message: ZerkDiagnosticMessage(
                message: message,
                diagnosticID: MessageID(domain: "ZerkMacros", id: id),
                severity: .error))
        diagnose(diagnostic)
    }
}
