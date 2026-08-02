//
//  FunctionParameterSyntaxExt.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

import SharedToolkit
import SwiftSyntax

extension FunctionParameterSyntax {
    /// Flattens Swift's two-name parameter syntax into a label plus an
    /// internal name.
    ///
    /// `f(label name: T)` writes both; `f(name: T)` writes one, which serves as
    /// both; `f(_ name: T)` suppresses the label entirely, recorded as `nil`.
    ///
    /// `locator` resolves the parameter's own position, so a diagnostic about it
    /// lands on the parameter and not on the enclosing declaration. It is
    /// optional because the synthesized memberwise initializer has parameters
    /// with no source of their own.
    func parameterRecord(locatedBy locator: ((Syntax) -> AttributeLocation)? = nil) -> ParameterRecord {
        let firstName = firstName.text
        let secondName = secondName?.text
        return ParameterRecord(
            label: firstName == "_" ? nil : firstName,
            name: secondName ?? firstName,
            typeKey: type.normalizedTypeKey,
            typeName: type.trimmedDescription,
            isAutoInjected: attributes.hasAttribute(named: "autoinjected"),
            location: locator.map { $0(Syntax(self)) })
    }
}
