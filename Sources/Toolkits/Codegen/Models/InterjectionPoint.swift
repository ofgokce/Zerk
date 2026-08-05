//
//  InterjectionPoint.swift
//  Zerk
//

/// One member's interjection point: the `Void` property declared so a key path
/// can name that member.
///
/// Replaces the requirement model behind the old `Interjecting<Key>` protocols.
/// A point carries no return type, no parameters and no isolation, because it
/// is never called — it exists only to be named. Everything those fields once
/// carried is now settled by the member itself.
struct InterjectionPoint {
    /// Where the point is declared, which is not always the key.
    enum Scope: Hashable {
        /// `extension Zerk<Key>.Interjection` — a key that is a type.
        case key(String)
        /// `extension Zerk.Interjection where Injectable: _$ZerkKey_Cache` — a
        /// generic key, which cannot be named in an extension header at all
        /// (`extension Zerk<Cache<E>>.Interjection` is "cannot find type 'E' in
        /// scope"). A generated marker protocol, conformed to by the base type
        /// unconditionally, scopes the point to exactly its specializations.
        case marker(protocolName: String, baseType: String)
    }

    let scope: Scope
    /// The point's name, unbackticked. See ``InterjectionPointName``.
    let name: String
}
