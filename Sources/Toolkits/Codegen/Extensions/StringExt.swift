//
//  StringExt.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

extension String {
    /// Lowercases the first character only, turning a type name into the
    /// generated member name that exposes it: `ApiService` -> `apiService`.
    var lowerCamelCased: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }

    /// The member name a type name gives: `ApiService` -> `apiService`,
    /// `Keychain.Store` -> `store`.
    ///
    /// A qualification says where the type lives, not what it is called, and
    /// `keychain.Store` is not an identifier — so only the last component
    /// survives. Nothing but a nested type reaches this with a dot in it.
    var memberNameForType: String {
        (split(separator: ".").last.map(String.init) ?? self).lowerCamelCased
    }

    /// Uppercases the first character only, for splicing a name into the middle
    /// of another: `foo` -> `Foo`, so `value` + `foo` reads `valueFoo`.
    var upperCamelCased: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
