//
//  MarkedParameter.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

/// A parameter of a member that carries `@injected` somewhere, plus whether
/// *this* parameter is one of the marked ones.
///
/// Unmarked parameters are kept because the generated overload must reproduce
/// them verbatim, `defaultText` included; marked ones are dropped from the
/// signature and resolved in the body instead.
struct MarkedParameter {
    let parameter: ParameterRecord
    let isMarked: Bool
    let defaultText: String?
}
