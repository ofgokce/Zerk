//
//  InterjectionPoint.swift
//  Zerk
//

/// One member's interjection point: the `Void` property declared on
/// `Zerk<Key>.Interjection` so a key path can name that member.
///
/// Replaces the requirement model behind the old `Interjecting<Key>` protocols.
/// A point carries no return type, no parameters and no isolation, because it
/// is never called — it exists only to be named. Everything those fields once
/// carried is now settled by the member itself.
struct InterjectionPoint {
    /// The key whose `Interjection` namespace declares it.
    let zerkArgument: String
    /// The point's name, unbackticked. See ``InterjectionPointName``.
    let name: String
}
