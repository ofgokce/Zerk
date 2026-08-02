//
//  KeyAliases.swift
//  Zerk
//

/// Collapses keys that `@ZerkAlias` / `#ZerkAlias` proved interchangeable into
/// one representative each.
///
/// Zerk matches dependencies by spelling, so without this a provider registered
/// as `Storing` would not satisfy a parameter written `Persisting`. Merging is
/// not merely a convenience: `Zerk<Storing>` and `Zerk<Persisting>` are the same
/// generic specialization, so leaving them apart emits two `inject()` members on
/// one type and the generated file does not compile.
///
/// Equivalence is transitive — `A = B` and `B = C` make one group of three — so
/// this is a union-find over canonical keys, resolved once and then applied to
/// every record before resolution runs.
struct KeyAliases {

    /// Canonical key -> the representative its group elected. Keys absent from
    /// any alias group do not appear; `representative(for:)` returns them
    /// unchanged.
    private let representatives: [String: String]
    /// Representative -> every spelling in its group, sorted, for diagnostics.
    private let groups: [String: [String]]

    static let empty = KeyAliases(declarations: [])

    var isEmpty: Bool { representatives.isEmpty }

    /// The key every member of `key`'s group is rewritten to.
    func representative(for key: String) -> String {
        representatives[key] ?? key
    }

    /// The other keys that merged into this representative, or empty when it is
    /// not the product of an alias. Used to explain a collision that a developer
    /// did not obviously write.
    func aliases(of representative: String) -> [String] {
        (groups[representative] ?? []).filter { $0 != representative }
    }

    init(declarations: [AliasDeclaration]) {
        var parent: [String: String] = [:]

        func find(_ key: String) -> String {
            var root = key
            while let next = parent[root], next != root {
                root = next
            }
            // Path compression keeps repeated lookups cheap on long alias
            // chains, which are rare but free to support.
            var current = key
            while let next = parent[current], next != root {
                parent[current] = root
                current = next
            }
            return root
        }

        func union(_ lhs: String, _ rhs: String) {
            let lhsRoot = find(lhs)
            let rhsRoot = find(rhs)
            if lhsRoot != rhsRoot {
                parent[rhsRoot] = lhsRoot
            }
        }

        // A key that appears as a typealias's left-hand side is a name for
        // something else, so it loses to any member that is not.
        var aliasOnly = Set<String>()

        for declaration in declarations {
            for key in declaration.keys where parent[key] == nil {
                parent[key] = key
            }
            if let aliasKey = declaration.aliasKey {
                aliasOnly.insert(aliasKey)
            }
            guard let first = declaration.keys.first else {
                continue
            }
            for key in declaration.keys.dropFirst() {
                union(first, key)
            }
        }

        var members: [String: [String]] = [:]
        for key in parent.keys {
            members[find(key), default: []].append(key)
        }

        var representatives: [String: String] = [:]
        var groups: [String: [String]] = [:]

        for (_, keys) in members {
            let sorted = keys.sorted()
            // Prefer a key that is nobody's alias — the underlying type rather
            // than a name for it. Alphabetical among equals, and alphabetical
            // overall if every member is an alias (which a cycle would produce).
            let underlying = sorted.filter { !aliasOnly.contains($0) }
            guard let elected = underlying.first ?? sorted.first else {
                continue
            }
            for key in sorted {
                representatives[key] = elected
            }
            groups[elected] = sorted
        }

        self.representatives = representatives
        self.groups = groups
    }
}
