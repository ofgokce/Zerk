//
//  ParameterClassifier.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 28.07.2026.
//

/// Decides, for every provider parameter, whether it is caller-supplied (E),
/// defaultable (S), or body-resolved (A).
///
/// This replaces the older mutually-recursive `defaults` / `externalParameters`
/// pair, which conflated "resolvable" with "defaultable" and so emitted
/// un-awaited `async` calls into default arguments.
struct ParameterClassifier {

    let values: [InjectableValueRecord]
    /// The provider `inject()` calls, per key — the only one a dependency may
    /// be resolved through. A key whose providers were ambiguous is absent, and
    /// parameters of that type fall back to **E**.
    ///
    /// A ``KeyIndex`` rather than a dictionary, so a dependency can also be
    /// answered by a generic registration covering its family. With none
    /// registered the two are the same lookup.
    let primaryResolutions: KeyIndex<ProviderResolution>

    /// Values grouped by `"key|name"`, which is what matching them takes.
    ///
    /// Grouped rather than a plain dictionary because the *count* is load-
    /// bearing: two values sharing a key and a name match neither, since a
    /// parameter demands a unique one.
    private let valuesByIdentity: [String: [InjectableValueRecord]]

    init(values: [InjectableValueRecord], primaryResolutions: KeyIndex<ProviderResolution>) {
        self.values = values
        self.primaryResolutions = primaryResolutions
        self.valuesByIdentity = Dictionary(grouping: values, by: \.matchIdentity)
    }

    /// `visiting` holds the injectable keys currently on the resolution stack.
    /// Classification is recursive — a parameter is only defaultable when its
    /// own provider needs no arguments — so a circular dependency would recurse
    /// forever without this guard. A key seen again mid-resolution is treated
    /// as external, which breaks the cycle; the cycle itself is reported
    /// separately by `cycleDiagnostics()`.
    func classify(_ resolution: ProviderResolution,
                  visiting: Set<String> = []) -> ProviderClassification {
        let memberIsolation = resolution.isolation
        let nextVisiting = visiting.union([resolution.injectableKey])

        var classified: [ClassifiedParameter] = []
        var crossDomainShared: [SharedDependency] = []
        var shared: [SharedDependency] = []
        var unresolvedAutoInjected: [ParameterRecord] = []
        var hasCrossing = false
        var isolatedDefault = false

        // `@autoinjected` on any parameter switches the provider to explicit
        // mode: Zerk resolves what was marked and nothing else. Unmarked, the
        // provider keeps the inferred behaviour, so this stays opt-in.
        let isExplicit = resolution.provider.parameters.contains(where: \.isAutoInjected)

        for parameter in resolution.provider.parameters {
            if isExplicit ? !parameter.isAutoInjected : parameter.isNonInjected {
                // Either deliberately unmarked while the provider is being
                // explicit, or explicitly opted out while it is inferring. The
                // caller supplies it even where Zerk could have resolved it,
                // which is the point of saying so.
                classified.append(ClassifiedParameter(parameter: parameter, binding: .external))
                continue
            }

            if isExplicit,
               injectableValue(matching: parameter) == nil,
               primaryResolutions[parameter] == nil {
                // Marked, but nothing in the module can satisfy it. Reported
                // against the parameter.
                //
                // A cycle needs no exclusion here: being *in* one means the key
                // resolves, so `primaryResolutions[parameter]` is non-nil and
                // this never runs. The guard that used to say so tested
                // `parameter.typeKey` against a set of registration keys, which
                // is the namespace confusion that cost a SIGSEGV further down —
                // dead here, but the wrong shape to leave lying around.
                unresolvedAutoInjected.append(parameter)
            }

            if let value = injectableValue(matching: parameter) {
                let hop = value.isolation.requiresHop(callingFrom: memberIsolation)
                // A value is *read*, never built, so there is nothing to
                // settle before using it — that is what makes it a value.
                let expression = value.resolutionExpression
                let effects = value.effects.merged(
                    with: ProviderEffects(isAsync: hop, isThrowing: false))

                if effects != .none {
                    hasCrossing = hasCrossing || hop
                    // A default argument cannot `try` or `await`, so anything
                    // effectful resolves in the body and the member takes the
                    // effects on.
                    classified.append(ClassifiedParameter(
                        parameter: parameter,
                        binding: .bodyResolved(
                            expression: "\(effects.callPrefix)\(expression)",
                            effects: effects
                        )
                    ))
                } else {
                    isolatedDefault = isolatedDefault || value.isolation.isGlobalActor
                    classified.append(ClassifiedParameter(
                        parameter: parameter,
                        binding: .defaulted(expression: expression)
                    ))
                }
                continue
            }

            // Resolve first, then test the *dependency's* key against
            // `visiting`. Testing the parameter's would compare a concrete
            // spelling (`Cache<String>`) against a set of registration keys,
            // which for a generic registration is a shape (`Cache<#0>`) — they
            // can never match, while `KeyIndex` resolves one to the other quite
            // happily. That combination recursed until the stack ran out.
            guard
                let dependency = primaryResolutions[parameter],
                !visiting.contains(dependency.injectableKey)
            else {
                classified.append(ClassifiedParameter(parameter: parameter, binding: .external))
                continue
            }

            let dependencyClassification = classify(dependency, visiting: nextVisiting)

            guard dependencyClassification.isFullyResolvable else {
                // The dependency itself needs arguments, so it cannot be
                // resolved on this provider's behalf.
                classified.append(ClassifiedParameter(parameter: parameter, binding: .external))
                continue
            }

            let hops = dependency.isolation.requiresHop(callingFrom: memberIsolation)
            // What the dependency's *member* costs to call, which for a kept
            // instance is not what building it cost — see
            // ``ProviderResolution/readEffects(building:)``. Asked here as well
            // as in `wrapperPlan` because this is where a parameter is judged
            // defaultable: a throwing-only `@Singleton` reads `async throws`,
            // and calling it from a default argument is not possible at all.
            let effects = dependency
                .readEffects(building: dependency.provider.effects
                    .merged(with: dependencyClassification.dependencyEffects))
                .merged(with: ProviderEffects(isAsync: hops, isThrowing: false))

            hasCrossing = hasCrossing || hops || dependencyClassification.hasIsolationCrossing
            isolatedDefault = isolatedDefault || dependencyClassification.usesIsolatedDefaultArgument
            shared += dependencyClassification.sharedDependencies
            crossDomainShared += dependencyClassification.crossDomainSharedDependencies

            if dependency.isShared {
                let entry = SharedDependency(typeName: dependency.typeName,
                                             scope: dependency.scope?.identity)
                shared.append(entry)
                if hops {
                    crossDomainShared.append(entry)
                }
            }

            let call = "\(effects.callPrefix)"
                + (dependency.provider.resolutionExpression(arguments: [])
                    ?? "Zerk<\(parameter.typeName)>.inject()")
            if effects == .none {
                // No effects means no hop, so member and dependency share a
                // domain: an isolated dependency here is exactly the SE-0411
                // same-domain isolated default argument.
                isolatedDefault = isolatedDefault || dependency.isolation.isGlobalActor
                classified.append(ClassifiedParameter(
                    parameter: parameter,
                    binding: .defaulted(expression: call)
                ))
            } else {
                classified.append(ClassifiedParameter(
                    parameter: parameter,
                    binding: .bodyResolved(expression: call, effects: effects)
                ))
            }
        }

        return ProviderClassification(
            parameters: classified,
            crossDomainSharedDependencies: uniqued(crossDomainShared),
            hasIsolationCrossing: hasCrossing,
            usesIsolatedDefaultArgument: isolatedDefault,
            sharedDependencies: uniqued(shared),
            unresolvedAutoInjected: unresolvedAutoInjected
        )
    }

    /// Order-preserving deduplication; the same kept instance can be reached
    /// through several paths.
    private func uniqued<Element: Hashable>(_ elements: [Element]) -> [Element] {
        var seen = Set<Element>()
        return elements.filter { seen.insert($0).inserted }
    }

    /// An `@InjectableValue` satisfies a parameter when both its key and its
    /// name match — the name match is what keeps two `String` values from
    /// being interchangeable.
    func injectableValue(matching parameter: ParameterRecord) -> InjectableValueRecord? {
        // Same reasoning as `KeyIndex[parameter]`: a bare generic parameter is
        // not a key, so a value that happens to be typed `E` must not answer it.
        guard !parameter.isBareGenericParameter else {
            return nil
        }
        let matches = valuesByIdentity["\(parameter.typeKey)|\(parameter.name)"] ?? []
        return matches.count == 1 ? matches[0] : nil
    }
}
