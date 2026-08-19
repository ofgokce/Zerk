//
//  ZerkGraph.swift
//  Zerk
//

import Foundation

/// The resolved dependency graph for one module, in the shape written to
/// `Zerk.graph.json`.
///
/// Zerk computes this graph on every build in order to emit code, and until now
/// threw it away. Nothing else can reconstruct it: a runtime container knows
/// what was registered but not what the compiler resolved, and reading the
/// generated Swift back gives you syntax rather than the decisions behind it —
/// which provider won a key, what each one depends on, how long each instance
/// lives.
///
/// Deliberately *descriptive*: it records what the generator concluded, never
/// what it wishes were true. Anything the emitted code does is visible here, and
/// nothing that isn't.
///
/// ## Stability
///
/// ``formatVersion`` is the contract. Fields may be added within a version;
/// removing or repurposing one requires bumping it. Consumers should ignore
/// unknown fields rather than fail on them.
///
/// **Optional fields are omitted, not written as `null`** — synthesized `Codable`
/// encodes them with `encodeIfPresent`, so a transient provider has no `scope`
/// key at all rather than `"scope": null`. `jq` and `Codable` treat the two
/// alike; a consumer indexing a dictionary directly should ask for the key
/// rather than subscript it.
///
/// ## Determinism
///
/// Every collection is sorted and nothing records a timestamp, so two builds of
/// identical sources produce byte-identical JSON. That is not tidiness: the file
/// is a build output, and one that changed every build would invalidate
/// downstream work and pollute every diff that touched it.
struct ZerkGraph: Codable, Equatable {

    /// Bumped only for a breaking change. See the type's discussion.
    ///
    /// 3 repurposed `Provider.isAsync` and `Provider.isThrowing`: they had
    /// reported how the *construction* was written, while the artifact claims
    /// to describe what is emitted. They now report what calling the generated
    /// member costs, which for an effectful kept instance is not the same
    /// answer.
    static let currentFormatVersion = 3

    var formatVersion: Int = ZerkGraph.currentFormatVersion
    /// The module this graph describes, when the caller named one.
    ///
    /// Zerk resolves per module, so a graph without this is ambiguous the
    /// moment two of them are in the same room — which is exactly what
    /// `swift package zerk graph` puts them in. The build plugin passes the
    /// target name; a hand invocation may omit it.
    var module: String? = nil
    /// Every key the module resolves, sorted by key.
    let keys: [Key]
    /// Every `@InjectableValue` in the module, sorted by key then name.
    let values: [Value]

    /// One injectable key, with every provider that satisfies it.
    struct Key: Codable, Equatable {
        /// The canonical key, as Zerk matches it — `any` stripped, sugar
        /// expanded. This is the identity; two spellings of one type share it.
        let key: String
        /// The key as it is written in generated code, which keeps `any`.
        let displayName: String
        /// `@Injectable(public: true)` — the generated members are `public`.
        let isExported: Bool
        /// Whether the key is satisfied by another module through
        /// `@ImportedInjectable`, in which case it has no local providers and
        /// nothing here builds it.
        let isImported: Bool
        /// Whether the key is generic, and so registered under a shape rather
        /// than a concrete type.
        let isGeneric: Bool
        /// The member backing `inject()`, or `nil` when the key is imported or
        /// its providers were ambiguous.
        let primaryMember: String?
        let providers: [Provider]
    }

    /// One way of building one key.
    struct Provider: Codable, Equatable {
        /// The type that owns the provider.
        let typeName: String
        /// The generated member's name — what `Zerk<Key>.<member>` is called,
        /// and what an interjection point is named after.
        let memberName: String
        /// `initializer`, `factory`, or `declaration` (a global or static
        /// `@Injectable` var/func registering a type it does not declare).
        let kind: String
        /// `transient`, `scoped`, or `singleton`.
        let lifetime: String
        /// The scope's name for a `@Scoped` provider, `nil` otherwise.
        let scope: String?
        /// The global actor this provider constructs on, or `nil` when
        /// nonisolated.
        let isolation: String?
        /// Whether calling this provider's generated member requires `await`.
        ///
        /// A property of the *emitted member*, not of the declaration it was
        /// written from, and the two part company in both directions a member
        /// gains effects: a dependency resolved into the body lends the member
        /// its `async`, and a kept instance is read back through
        /// `ZerkAsyncBox`, which suspends however the construction was written.
        /// A `@Singleton` whose initializer only `throws` is emitted as
        /// `async throws` and reported here as both.
        let isAsync: Bool
        /// Whether calling this provider's generated member requires `try`. Read
        /// off the emitted member, as ``isAsync`` is.
        let isThrowing: Bool
        /// Whether this provider backs the key's `inject()`.
        let isPrimary: Bool
        let location: Location
        /// The `#if` expression this provider's generated member is emitted
        /// under, or absent when it is unconditional.
        ///
        /// A graph that omitted this would claim a key is resolvable in builds
        /// where nothing resolves it. Zerk does not evaluate the expression —
        /// see `CompilationCondition` — so this is the text, for a reader or a
        /// tool that knows the build settings Zerk does not.
        var condition: String? = nil
        /// One entry per provider parameter, in declaration order.
        let dependencies: [Dependency]
    }

    /// How one provider parameter gets its value.
    struct Dependency: Codable, Equatable {
        let parameterName: String
        let typeName: String
        /// What satisfies it:
        ///
        /// - `injectable` — another key in the graph, named by ``key``. This is
        ///   the edge worth walking.
        /// - `value` — an `@InjectableValue`, named by ``valueName``.
        /// - `caller` — nothing in the module resolves it, so it bubbles up as
        ///   a parameter of the generated member. Not a hole in the graph: it is
        ///   the graph's boundary.
        let source: String
        /// The key resolved, for `injectable` and `value`.
        let key: String?
        /// The value's name, for `value` — values are matched by name as well
        /// as key, so the key alone does not identify one.
        let valueName: String?
    }

    /// One `@InjectableValue`.
    struct Value: Codable, Equatable {
        let name: String
        let key: String
        let displayName: String
        let isExported: Bool
        let isImported: Bool
        /// `copied` or `referenced`.
        let injectionMethod: String
        let isolation: String?
        let isAsync: Bool
        let isThrowing: Bool
        let location: Location
        /// The `#if` expression the value's member is emitted under, or absent
        /// when it is unconditional. See ``Provider/condition``.
        var condition: String? = nil
    }

    /// Where a declaration sits, so a consumer can link back to source.
    ///
    /// Paths are recorded exactly as the compiler was given them, which for a
    /// SwiftPM build is absolute. Consumers wanting repo-relative paths should
    /// relativize against their own root rather than expect Zerk to guess it.
    struct Location: Codable, Equatable {
        let file: String
        let line: Int
        let column: Int
    }

    /// The artifact's bytes.
    ///
    /// Sorted keys and pretty printing are both for the reader: this file is
    /// meant to be opened, diffed and grepped, not only parsed. Without
    /// `.sortedKeys` the field order follows `Codable` synthesis and would be
    /// stable but arbitrary.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
