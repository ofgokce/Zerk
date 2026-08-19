//
//  InterjectionPointName.swift
//  Zerk
//

/// How a generated member's interjection point is named.
///
/// The name *is* the member's signature, carried by a raw identifier (SE-0451)
/// rather than encoded into something identifier-safe:
///
/// ```swift
/// static var live: Loading                     ->  `live`
/// static func seeded(seed: Int) -> Loading     ->  `seeded(seed: Int)`
/// ```
///
/// Shared because two sides have to agree on it: the build plugin declares the
/// points, and the interjection macros name them. Since a macro emits a *key
/// path*, disagreeing is a compile error at the interjection — `type
/// 'Zerk<…>.Interjection' has no member 'seeded(seed:Int)'` — rather than a
/// lookup that silently finds nothing, so the two can never drift apart in
/// silence.
///
/// Nothing needs escaping. The only characters a raw identifier forbids —
/// backtick, backslash, newline, and the non-printables — cannot occur in Swift
/// type syntax, and two members of one key with identical signatures are
/// already rejected as a collision.
public enum InterjectionPointName {

    /// The point's name, unbackticked.
    ///
    /// - Parameters:
    ///   - member: the generated member's name, e.g. `seeded`.
    ///   - parameters: each rendered as it appears in the signature, e.g.
    ///     `seed: Int`. Empty for a property-shaped member, whose point is
    ///     simply its name.
    public static func text(member: String, parameters: [String]) -> String {
        guard !parameters.isEmpty else {
            return member
        }
        return "\(member)(\(parameters.joined(separator: ", ")))"
    }

    /// The selector form — labels only, as Swift itself writes a function
    /// reference: `loader(store:)`. Enough whenever a name's overloads differ by
    /// their labels, which is the usual way they differ.
    public static func selector(member: String, labels: [String]) -> String {
        guard !labels.isEmpty else {
            return "\(member)()"
        }
        return "\(member)(\(labels.map { "\($0):" }.joined()))"
    }

    /// The point as written in source — always backticked, since escaping a
    /// plain identifier changes nothing and one rule beats two.
    public static func escaped(member: String, parameters: [String]) -> String {
        "`\(text(member: member, parameters: parameters))`"
    }
}
