//
//  CompilationCondition.swift
//  Zerk
//

/// The `#if` clauses a declaration sits inside, outermost first.
///
/// Zerk does not evaluate these. It cannot: the plugin has no access to the
/// target's active compilation conditions, and SwiftPM caches a plugin's result
/// across build configurations, so a `DEBUG` answered once would be baked into
/// the Release build too. What Zerk does instead is *carry* the conditions —
/// every declaration it generates for a conditional registration is emitted
/// under the same guard, and the compiler decides, with the knowledge Zerk
/// lacks.
///
/// Two things follow from that, and they are the whole feature:
///
/// - Generated code for a registration inside `#if DEBUG` is itself inside
///   `#if DEBUG`, so a Release build neither builds it nor names the type.
/// - Registrations in different clauses of one `#if` never compete for a key,
///   because no build ever sees both. That is what makes the DEBUG/Release
///   swap — the reason this exists — resolve rather than collide.
struct CompilationCondition: Hashable {
    /// Outermost first, so the guards read in source order when joined.
    var clauses: [ConditionClause] = []

    static let unconditional = CompilationCondition()

    var isUnconditional: Bool { clauses.isEmpty }

    /// Orders conditions by where they were written.
    ///
    /// Anything emitting one declaration per clause has to pick an order, and it
    /// has to be the same on every build. Sorting the guard *text* would put
    /// `#else` first, since `!` sorts before `(` — so this sorts by position
    /// instead, which puts the clauses back in the order they were written.
    var sortKey: String {
        clauses.map { "\($0.branch)|\(Self.padded($0.index))" }.joined(separator: "/")
    }

    /// Fixed-width digits, so a lexicographic compare orders them as numbers.
    static func padded(_ value: Int, width: Int = 9) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }

    /// The `#if` expression guarding a declaration in this position, or `nil`
    /// when it needs no guard.
    ///
    /// Nested `#if`s become one conjunction rather than nested blocks: the
    /// generated file is emitted line by line and a single guard is one line at
    /// each end, which keeps the wrapping local to whatever is being wrapped.
    var guardText: String? {
        let parts = clauses.map(\.guardText).filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " && ")
    }

    /// The clauses every one of these positions sits inside.
    ///
    /// What a whole `extension Zerk<Key> { … }` can be guarded by: if every
    /// provider of the key is inside `#if DEBUG`, so is the extension — which
    /// matters when the key's own type is declared there too and naming it in a
    /// Release build would not compile.
    ///
    /// Empty for a `#if`/`#else` pair, which is the point: those two share no
    /// clause, so the extension stays unguarded and each member carries its own
    /// guard. Guarding the extension with their disjunction would be true in
    /// every build anyway, and would say nothing.
    static func commonPrefix(of conditions: [CompilationCondition]) -> CompilationCondition {
        guard let first = conditions.first else {
            return .unconditional
        }
        var prefix = first.clauses
        for condition in conditions.dropFirst() {
            var shared: [ConditionClause] = []
            for (left, right) in zip(prefix, condition.clauses) {
                guard left == right else {
                    break
                }
                shared.append(left)
            }
            prefix = shared
            if prefix.isEmpty {
                break
            }
        }
        return CompilationCondition(clauses: prefix)
    }

    /// What is left to guard once an enclosing block already guards `prefix`.
    ///
    /// Nesting `#if DEBUG` inside `#if DEBUG` would compile, but it reads as two
    /// independent conditions that happen to match, and the generated file is
    /// something people read.
    func dropping(prefix: CompilationCondition) -> CompilationCondition {
        guard clauses.count >= prefix.clauses.count,
              Array(clauses.prefix(prefix.clauses.count)) == prefix.clauses else {
            return self
        }
        return CompilationCondition(clauses: Array(clauses.dropFirst(prefix.clauses.count)))
    }

    /// Whether no build configuration can see both of these at once.
    ///
    /// Answered structurally, never by evaluating anything: two positions are
    /// exclusive when they sit in *different clauses of the same `#if`*, which
    /// is the one case where mutual exclusion is a fact about the source rather
    /// than about the build settings. `#if DEBUG` versus a separate `#if !DEBUG`
    /// is *not* recognised — the conditions are opposites to a reader, but
    /// proving it would mean evaluating `DEBUG`, which is exactly what Zerk
    /// cannot do.
    ///
    /// The asymmetry is deliberate. A false "these are exclusive" would silence
    /// a real ambiguity and pick a provider arbitrarily; a false "these can
    /// coexist" only asks the developer to write `#else`, and says so.
    static func areExclusive(_ lhs: CompilationCondition, _ rhs: CompilationCondition) -> Bool {
        for left in lhs.clauses {
            for right in rhs.clauses
            where left.branch == right.branch && left.index != right.index {
                return true
            }
        }
        return false
    }
}

/// One clause of one `#if`.
struct ConditionClause: Hashable {
    /// Identity of the `#if` this clause belongs to — its file and offset.
    ///
    /// Clause exclusivity is decided by comparing these, so it has to name the
    /// `#if` itself rather than its condition: two separate `#if DEBUG` blocks
    /// are different branches whose clauses can both be active.
    let branch: String
    /// Position within that `#if`: 0 is the `#if` clause, then each `#elseif`,
    /// then `#else`.
    let index: Int
    /// What this clause alone states, or `nil` for `#else`.
    let condition: String?
    /// The conditions of the clauses before it, all of which must be false for
    /// this one to be active.
    let precedingConditions: [String]

    /// The guard to emit for a declaration in this clause.
    ///
    /// An `#elseif` is only active when every earlier condition failed, and an
    /// `#else` is *nothing but* those failures — so the preceding conditions are
    /// part of the guard, not context. Emitting `(BETA)` for `#elseif BETA`
    /// would widen the clause to also cover builds where `DEBUG` held.
    ///
    /// Every condition is parenthesised before it is combined, because the
    /// conditions are the developer's own text: an unwrapped `A || B` under a
    /// `&&` would bind the wrong way round.
    var guardText: String {
        var parts = precedingConditions.map { "!(\($0))" }
        if let condition {
            parts.append("(\(condition))")
        }
        return parts.joined(separator: " && ")
    }
}
