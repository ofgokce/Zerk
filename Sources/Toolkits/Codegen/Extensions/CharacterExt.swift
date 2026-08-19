//
//  CharacterExt.swift
//  Zerk
//

extension Character {
    /// Whether this could begin a Swift identifier.
    ///
    /// An approximation, and deliberately a permissive one: it is used to walk
    /// canonical key text, where the alternative to a letter or `_` is always
    /// punctuation Zerk itself put there (`<`, `>`, `.`, `,`, `&`, `(`, `)`,
    /// `-`, `?`, spaces).
    var isZerkIdentifierStart: Bool {
        isLetter || self == "_"
    }

    var isZerkIdentifierContinuation: Bool {
        isLetter || isNumber || self == "_"
    }
}
