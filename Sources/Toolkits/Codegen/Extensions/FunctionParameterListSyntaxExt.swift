//
//  FunctionParameterListSyntaxExt.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

import SwiftSyntax

extension FunctionParameterListSyntax {
    var parameterRecords: [ParameterRecord] {
        map(\.parameterRecord)
    }
}
