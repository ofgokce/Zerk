//
//  FunctionParameterListSyntaxExt.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

import SwiftSyntax

extension FunctionParameterListSyntax {
    func parameterRecords(locatedBy locator: ((Syntax) -> AttributeLocation)? = nil) -> [ParameterRecord] {
        map { $0.parameterRecord(locatedBy: locator) }
    }
}
