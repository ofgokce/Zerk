//
//  KeyShape.swift
//  Zerk
//

/// A key with its generic arguments holed out: `Cache<String>` and `Cache<Int>`
/// share the shape `Cache<#0>`.
///
/// This is the key a *generic* registration is filed under. A declaration
/// `struct Cache<E>` cannot register under `Cache<E>` — two modules spelling the
/// parameter `E` and `Element` would file one family under two keys — and cannot
/// register under the bare `Cache`, which is not a type and would collide with a
/// non-generic `Cache`. Holing the arguments out gives one key per family,
/// independent of what the author named the parameters.
///
/// The hole is spelled with `#` because **a shape must not be writable**. `_`
/// was the obvious choice and is wrong: SE-0315 type placeholders make
/// `let c: Cache<_> = …` legal, and `inferredStructInitializer` reads exactly
/// those annotations — so `Cache<_>` is a key a real declaration can produce. No
/// type can contain `#`.
public enum KeyShape {

    /// `Cache<#0>`, `Store<#0, #1>`.
    public static func text(base: String, arity: Int) -> String {
        guard arity > 0 else {
            return base
        }
        let holes = (0..<arity).map { "#\($0)" }.joined(separator: ", ")
        return "\(base)<\(holes)>"
    }

    /// Whether a key is a shape rather than a type. Sound in both directions,
    /// since `#` is unwritable in a type and every shape of arity > 0 has one.
    public static func isShape(_ key: String) -> Bool {
        key.contains("<#")
    }
}
