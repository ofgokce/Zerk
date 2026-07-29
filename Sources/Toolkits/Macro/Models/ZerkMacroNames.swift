//
//  ZerkMacroNames.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 28.07.2026.
//

/// Attribute spellings shared by the macros and the build plugin.
///
/// The two read the same source independently, so a name that drifts between
/// them would silently stop matching rather than fail to compile.
public enum ZerkMacroNames {
    public static let injectableAttributeName = "Injectable"
    public static let providingAttributeName = "Providing"
}
