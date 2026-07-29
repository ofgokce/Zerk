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
    var parameterRecord: ParameterRecord {
        let firstName = firstName.text
        let secondName = secondName?.text
        return ParameterRecord(
            label: firstName == "_" ? nil : firstName,
            name: secondName ?? firstName,
            typeKey: type.normalizedTypeKey,
            typeName: type.trimmedDescription)
    }
}
