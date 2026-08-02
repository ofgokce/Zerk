//
//  ProviderClassification.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 28.07.2026.
//

/// How one provider parameter gets its value in the generated member.
///
/// This is the E/S/A partition: a dependency is exposed as a *defaulted*
/// parameter only when its resolution is a plain expression. Anything needing
/// `await`, `try`, or an isolation hop is resolved in the member body instead,
/// because a default argument expression cannot contain `await` at all.
enum ParameterBinding: Equatable {
    /// **E** — nothing in the module resolves it; the caller supplies it.
    case external
    /// **S** — resolvable by an expression usable as a default argument.
    case defaulted(expression: String)
    /// **A** — resolvable, but resolution carries effects or crosses an
    /// isolation domain, so it happens in the body and contributes effects.
    case bodyResolved(expression: String, effects: ProviderEffects)
}

/// One provider parameter together with the binding chosen for it.
struct ClassifiedParameter: Equatable {
    let parameter: ParameterRecord
    let binding: ParameterBinding
}

/// The E/S/A partition of one provider's parameters, plus the facts about the
/// resolution that only become knowable once every parameter is classified.
struct ProviderClassification {
    let parameters: [ClassifiedParameter]

    /// Effects contributed by body-resolved dependencies. Merged with the
    /// provider's own effects to give the resolving variant's effects.
    var dependencyEffects: ProviderEffects {
        parameters.reduce(ProviderEffects.none) { total, classified in
            if case .bodyResolved(_, let effects) = classified.binding {
                return total.merged(with: effects)
            }
            return total
        }
    }

    /// Names of `@Singleton` types this provider depends on across an isolation
    /// boundary. A singleton is shared by definition, so its region is not
    /// disconnected and the compiler will require it to be `Sendable`.
    let crossDomainSingletonDependencies: [String]

    /// Whether any dependency had to be reached across an isolation boundary.
    let hasIsolationCrossing: Bool

    /// Whether any **S** binding resolves to a global-actor-isolated expression
    /// — i.e. the generated signature carries an isolated default argument.
    ///
    /// This is the one construct SE-0411 governs, so it is the one construct a
    /// Swift 5 language mode target can reject. A default that resolves to a
    /// *nonisolated* expression is fine in every language mode, even on an
    /// isolated member, so this deliberately tracks the **dependency's**
    /// isolation rather than the member's.
    let usesIsolatedDefaultArgument: Bool

    /// Every `@Singleton` reachable through this provider's dependencies,
    /// transitively. A shared instance anywhere in the graph means the
    /// constructed value's region is not disconnected, so its result cannot be
    /// returned as `sending`.
    let singletonDependencies: [String]

    /// Parameters marked `@autoinjected` that nothing in the module can satisfy.
    ///
    /// Carried out rather than reported here, because `classify` runs several
    /// times per provider — for the member, for `inject()`, and recursively for
    /// anything depending on it — and each run would report the same parameter
    /// again. `GeneratorOutputBuilder` emits them once.
    var unresolvedAutoInjected: [ParameterRecord] = []

    /// **E** — parameters the caller must supply, which become the generated
    /// member's own parameters.
    var externals: [ParameterRecord] {
        parameters.compactMap { $0.binding == .external ? $0.parameter : nil }
    }

    /// **A** — parameters resolved in the member body because their resolution
    /// carries effects.
    var bodyResolved: [ClassifiedParameter] {
        parameters.filter {
            if case .bodyResolved = $0.binding { return true }
            return false
        }
    }

    /// Whether Zerk can build this with no help from the caller. A dependency
    /// that is not fully resolvable cannot be resolved on another provider's
    /// behalf, so it falls back to **E**.
    var isFullyResolvable: Bool {
        externals.isEmpty
    }

    /// Whether the member must be emitted as two variants — one taking every
    /// parameter, one resolving the **A** partition in its body.
    var requiresSplit: Bool {
        !bodyResolved.isEmpty
    }

    /// Default expressions keyed by parameter name, for the emitted signature.
    var defaultExpressions: [String: String] {
        var result: [String: String] = [:]
        for classified in parameters {
            if case .defaulted(let expression) = classified.binding {
                result[classified.parameter.name] = expression
            }
        }
        return result
    }

    /// Parameters that appear in the *resolving* variant's signature: E and S,
    /// but not A.
    var resolvingVariantParameters: [ParameterRecord] {
        parameters.compactMap { classified in
            if case .bodyResolved = classified.binding { return nil }
            return classified.parameter
        }
    }
}
