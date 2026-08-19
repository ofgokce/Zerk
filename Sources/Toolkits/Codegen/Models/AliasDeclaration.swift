//
//  AliasDeclaration.swift
//  Zerk
//

/// One `@ZerkAlias` or `#ZerkAlias` declaration, as collected from source.
///
/// Both forms say the same thing — these keys are one key — and differ only in
/// what they can tell us about *naming*. A typealias has a left-hand side that
/// is, by construction, an alias rather than a type of its own, which is what
/// lets `KeyAliases` prefer the underlying spelling when it picks a
/// representative. A `#ZerkAlias` list has no such structure; its members are
/// peers.
struct AliasDeclaration {
    /// The canonical keys this declaration relates, in source order.
    let keys: [String]
    /// The key that is merely a name for the others — a typealias's left-hand
    /// side. `nil` for `#ZerkAlias`, whose entries are all peers.
    let aliasKey: String?
    let location: AttributeLocation
}
