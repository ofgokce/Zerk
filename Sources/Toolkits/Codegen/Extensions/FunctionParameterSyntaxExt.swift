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
    ///
    /// `genericScope` is the enclosing declarations' generic parameters, which
    /// decide whether this parameter's type is one key, a family of keys, or a
    /// bare parameter that is none. Empty for every non-generic type, so the
    /// default keeps existing callers exact.
    func parameterRecord(locatedBy locator: ((Syntax) -> AttributeLocation)? = nil,
                         genericScope: Set<String> = []) -> ParameterRecord {
        let firstName = firstName.text
        let secondName = secondName?.text
        return ParameterRecord(
            label: firstName == "_" ? nil : firstName,
            name: secondName ?? firstName,
            typeKey: type.normalizedTypeKey,
            typeName: type.trimmedDescription,
            isAutoInjected: attributes.hasAttribute(named: "autoinjected"),
            isNonInjected: attributes.hasAttribute(named: "noninjected"),
            feedsDependencies: attributes.hasAttribute(named: "injectable"),
            location: locator.map { $0(Syntax(self)) },
            typeKeyShape: type.typeKeyShape,
            mentionedGenericParameters: type.mentionedGenericParameters(in: genericScope),
            isBareGenericParameter: type.isBareGenericParameter(in: genericScope))
    }
}
