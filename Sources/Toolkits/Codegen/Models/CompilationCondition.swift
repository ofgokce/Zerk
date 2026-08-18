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

    /// Whether some clause of this position requires `condition` to hold.
    ///
    /// This and ``denies(_:)`` are the two halves every question about
    /// coexistence is asked in: ``areExclusive(_:_:)`` compares them pairwise,
    /// and `ProviderResolver.coexisting` splits candidates on a condition one
    /// asserts and another denies. Keeping both readers on the same pair is
    /// what stops the two from drifting into different notions of "exclusive" —
    /// which they had, and it cost a Release build its `inject()`.
    func asserts(_ condition: String) -> Bool {
        clauses.contains { $0.condition == condition }
    }

    /// Whether some clause of this position is reached only because `condition`
    /// failed — the `#else` and `#elseif` side of ``asserts(_:)``.
    func denies(_ condition: String) -> Bool {
        clauses.contains { $0.precedingConditions.contains(condition) }
    }

    /// Every condition named anywhere in this position, asserted or denied.
    var mentionedConditions: (asserted: Set<String>, denied: Set<String>) {
        var asserted: Set<String> = []
        var denied: Set<String> = []
        for clause in clauses {
            if let condition = clause.condition {
                asserted.insert(condition)
            }
            denied.formUnion(clause.precedingConditions)
        }
        return (asserted, denied)
    }

    /// Whether this position is live under an assignment of truth values to
    /// condition texts.
    ///
    /// The assignment is a *hypothetical* build configuration, not one Zerk
    /// knows anything about — which is why the only thing built on this is a
    /// search for a configuration that would break, never a claim about which
    /// configuration you are in.
    func holds(under assignment: [String: Bool]) -> Bool {
        clauses.allSatisfy { clause in
            clause.precedingConditions.allSatisfy { assignment[$0] == false }
                && (clause.condition.map { assignment[$0] == true } ?? true)
        }
    }

    /// A configuration that reaches `consumer` and none of `providers`, or `nil`
    /// when every configuration reaching the consumer has one.
    ///
    /// Answered by enumerating truth assignments over the condition *texts*
    /// involved, which is exact for the fact it is asked to establish: whether
    /// `#if DEBUG` and its `#else` between them cover everything (they do),
    /// whether `#if os(iOS)` and `#if os(macOS)` do (Zerk cannot say they do),
    /// whether a consumer under `#if DEBUG` is served by a provider under a
    /// different `#if DEBUG` (it is).
    ///
    /// Texts are treated as **independent**, so `#if DEBUG` and a separate
    /// `#if !DEBUG` leave a hole where both are false. That is the same refusal
    /// to read a negation the rest of this type makes, and it errs the same way:
    /// what Zerk cannot prove covered, it says so about, and the fix is to write
    /// the second one as an `#else`.
    ///
    /// Returns `nil` past ``assignmentAtomLimit`` distinct texts rather than
    /// enumerating an exponential number of them. A module that conditional
    /// enough is beyond what this can usefully say, and refusing to answer is
    /// the harmless direction.
    static func uncoveredConfiguration(of consumer: CompilationCondition,
                                       by providers: [CompilationCondition]) -> [String: Bool]? {
        // The overwhelmingly common shape, and worth not paying for: anything
        // unconditional is live in every configuration there is.
        if providers.contains(where: \.isUnconditional) {
            return nil
        }

        var atoms: Set<String> = consumer.atoms
        for provider in providers {
            atoms.formUnion(provider.atoms)
        }
        let ordered = atoms.sorted()
        guard ordered.count <= assignmentAtomLimit else {
            return nil
        }

        for mask in 0..<(1 << ordered.count) {
            var assignment: [String: Bool] = [:]
            for (offset, atom) in ordered.enumerated() {
                assignment[atom] = mask & (1 << offset) != 0
            }
            guard consumer.holds(under: assignment),
                  !providers.contains(where: { $0.holds(under: assignment) }) else {
                continue
            }
            return assignment
        }
        return nil
    }

    /// How many distinct condition texts ``uncoveredConfiguration(of:by:)`` will
    /// enumerate over. 2^12 is instant; the limit is there so a pathological
    /// module cannot make codegen the slow part of a build.
    static let assignmentAtomLimit = 12

    /// Every distinct condition text this position names, asserted or denied.
    var atoms: Set<String> {
        let mentioned = mentionedConditions
        return mentioned.asserted.union(mentioned.denied)
    }

    /// Whether no build configuration can see both of these at once.
    ///
    /// Answered structurally, never by evaluating anything — see
    /// ``ConditionClause/contradicts(_:)`` for the two facts that qualify.
    /// `#if DEBUG` versus a separate `#if !DEBUG` is still *not* recognised: the
    /// conditions are opposites to a reader, but proving it would mean
    /// evaluating `DEBUG`, which is exactly what Zerk cannot do.
    ///
    /// The remaining asymmetry is deliberate. A false "these are exclusive"
    /// would silence a real ambiguity and pick a provider arbitrarily; a false
    /// "these can coexist" only asks the developer to write `#else`, and says
    /// so.
    static func areExclusive(_ lhs: CompilationCondition, _ rhs: CompilationCondition) -> Bool {
        for left in lhs.clauses {
            for right in rhs.clauses where left.contradicts(right) {
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
    /// Names the `#if` itself rather than its condition, so that two separate
    /// `#if DEBUG` blocks are different branches: their clauses line up one to
    /// one, and every pair of them can be active together.
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

    /// Whether no build can have both this clause and `other` active.
    ///
    /// Two facts qualify, and neither is an evaluation:
    ///
    /// - **Different clauses of one `#if`.** The compiler picks exactly one,
    ///   whatever the conditions say.
    /// - **One clause asserts what the other requires to have failed.** A
    ///   clause is active when its own condition holds *and* every condition
    ///   before it in its `#if` did not; so a clause stating `DEBUG` and a
    ///   clause reached only because `DEBUG` failed cannot both be live —
    ///   across separate `#if`s as much as within one.
    ///
    /// The second rests on identical condition *text* meaning an identical
    /// answer, which holds because every condition Swift accepts here is a
    /// property of the compilation: `-D` flags, `os`, `arch`, `swift`,
    /// `compiler`, `canImport`. None of them varies between two points in one
    /// module, so `#if DEBUG` in one file and `#if DEBUG` in another are live
    /// together or not at all. Text that differs at all is simply not matched,
    /// which falls back to "these can coexist".
    ///
    /// Without it, a conditional protocol near the top of a file and its
    /// conditional implementations further down — two `#if` blocks, the natural
    /// way to write the pair — made the `#else` declaration count against the
    /// `#if` branch, which demoted a legitimately public export and warned about
    /// it.
    func contradicts(_ other: ConditionClause) -> Bool {
        guard branch != other.branch else {
            return index != other.index
        }
        if let condition, other.precedingConditions.contains(condition) {
            return true
        }
        if let otherCondition = other.condition, precedingConditions.contains(otherCondition) {
            return true
        }
        return false
    }
}
