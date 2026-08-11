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
///
/// ## Module qualification
///
/// The same job, for a spelling nobody declares: `Core.ApiServicing` and
/// `ApiServicing` are one type, and Zerk matched them as two keys — so a
/// provider registered unqualified would not satisfy a parameter written with
/// the module name, and the dependency silently bubbled up to the caller
/// instead.
///
/// Stripping is safe for exactly the modules the *generated file imports*, which
/// is what ``knownModules`` carries. Two facts make that the right boundary:
/// inside a file that imports `Core`, the two spellings are interchangeable by
/// definition, and the short spelling that comes out of this must still resolve
/// where Zerk emits it — which it does, because the generated file imports the
/// same module. A prefix from a module nobody imported is left alone, since it
/// may well be a nested type rather than a module at all.
///
/// ``implicitModules`` is the exception, and `Swift` is the whole of it.
struct KeyAliases {

    /// Canonical key -> the representative its group elected. Keys absent from
    /// any alias group do not appear; `representative(for:)` returns them
    /// unchanged.
    private let representatives: [String: String]
    /// Representative -> every spelling in its group, sorted, for diagnostics.
    private let groups: [String: [String]]

    /// Modules whose qualifier may be dropped from a key. See the type's
    /// discussion.
    private let knownModules: Set<String>

    /// Modules that never have to be declared, because they are in scope
    /// everywhere without anyone asking.
    ///
    /// `Swift` alone. It is implicitly imported into every Swift file —
    /// including the one Zerk generates — so `Swift.String` and `String` name
    /// the same type in every context that matters, and the short spelling this
    /// leaves behind always resolves. Requiring `#ZerkImport(module: "Swift")`
    /// for that would be asking a developer to declare something the language
    /// already guarantees.
    ///
    /// Nothing else belongs here, `Foundation` included. Every other module has
    /// to actually be imported before its short names mean anything in the
    /// generated file, and Zerk emitting an import nobody asked for is a
    /// different decision from Zerk *reading* one that was.
    static let implicitModules: Set<String> = ["Swift"]

    static let empty = KeyAliases(declarations: [])

    /// The key every member of `key`'s group is rewritten to.
    ///
    /// Qualifiers come off *first*, so the two mechanisms compose: an alias
    /// declared against `Foo` still catches a use written `Core.Foo`.
    func representative(for key: String) -> String {
        let unqualified = Self.unqualified(key, modules: knownModules)
        return representatives[unqualified] ?? unqualified
    }

    /// `Core.Foo` -> `Foo`, for every known module, anywhere a type reference
    /// begins.
    ///
    /// Works on the canonical key text rather than on syntax because that is
    /// where every comparison happens, and because a key reaches this having
    /// already been flattened — `Array<Core.Foo>` and `(Core.A) -> Core.B` both
    /// need the same treatment and neither survives as a tree.
    ///
    /// A qualifier is only dropped where a type reference *starts*: never after
    /// a dot. `Core.Outer.Inner` loses its module and keeps its nesting, and a
    /// nested type that happens to share a module's name is untouched.
    static func unqualified(_ key: String, modules: Set<String>) -> String {
        guard !modules.isEmpty, key.contains(".") else {
            return key
        }

        var result = ""
        var index = key.startIndex
        // Whether the next identifier begins a type reference, as opposed to
        // continuing a dotted one.
        var startsReference = true

        while index < key.endIndex {
            let character = key[index]

            guard character.isZerkIdentifierStart else {
                result.append(character)
                startsReference = character != "."
                index = key.index(after: index)
                continue
            }

            var end = index
            while end < key.endIndex, key[end].isZerkIdentifierContinuation {
                end = key.index(after: end)
            }
            let word = key[index..<end]

            if startsReference, end < key.endIndex, key[end] == ".", modules.contains(String(word)) {
                // Drop the qualifier *and* its dot, leaving what follows still
                // at the start of a reference.
                index = key.index(after: end)
                continue
            }

            result.append(contentsOf: word)
            index = end
            startsReference = false
        }

        return result
    }

    /// The other keys that merged into this representative, or empty when it is
    /// not the product of an alias. Used to explain a collision that a developer
    /// did not obviously write.
    func aliases(of representative: String) -> [String] {
        (groups[representative] ?? []).filter { $0 != representative }
    }

    init(declarations: [AliasDeclaration], knownModules: Set<String> = []) {
        self.knownModules = knownModules.union(Self.implicitModules)
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
            // Unqualified up front, so a `@ZerkAlias` written against
            // `Core.Foo` joins the same group as one written against `Foo`.
            let keys = declaration.keys.map { Self.unqualified($0, modules: knownModules) }
            for key in keys where parent[key] == nil {
                parent[key] = key
            }
            if let aliasKey = declaration.aliasKey {
                aliasOnly.insert(Self.unqualified(aliasKey, modules: knownModules))
            }
            guard let first = keys.first else {
                continue
            }
            for key in keys.dropFirst() {
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
