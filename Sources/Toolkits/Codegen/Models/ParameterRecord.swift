//
//  ParameterRecord.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

/// One parameter of a provider.
///
/// `typeKey` is the normalized spelling, used to *match* the parameter against
/// a registered injectable; `typeName` is the spelling as written, used when
/// emitting it back out. Keeping both means matching is insensitive to
/// whitespace without the generated code losing the developer's formatting.
struct ParameterRecord: Equatable {
    let label: String?
    let name: String
    let typeKey: String
    let typeName: String
}
