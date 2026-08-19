//
//  FunctionParameterListSyntaxExt.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

import SwiftSyntax

extension FunctionParameterListSyntax {
    func parameterRecords(locatedBy locator: ((Syntax) -> AttributeLocation)? = nil,
                          genericScope: Set<String> = []) -> [ParameterRecord] {
        map { $0.parameterRecord(locatedBy: locator, genericScope: genericScope) }
    }
}
