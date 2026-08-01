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
    let primaryResolutions: [String: ProviderResolution]

    init(values: [InjectableValueRecord], primaryResolutions: [String: ProviderResolution]) {
        self.values = values
        self.primaryResolutions = primaryResolutions
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
        var crossDomainSingletons: [String] = []
        var singletons: [String] = []
        var hasCrossing = false
        var isolatedDefault = false

        for parameter in resolution.provider.parameters {
            if let value = injectableValue(matching: parameter) {
                let expression = "Zerk<\(value.typeName)>.\(value.name)"
                if value.isolation.requiresHop(callingFrom: memberIsolation) {
                    hasCrossing = true
                    classified.append(ClassifiedParameter(
                        parameter: parameter,
                        binding: .bodyResolved(
                            expression: "await \(expression)",
                            effects: ProviderEffects(isAsync: true, isThrowing: false)
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

            guard
                !visiting.contains(parameter.typeKey),
                let dependency = primaryResolutions[parameter.typeKey]
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
            let effects = dependency.provider.effects
                .merged(with: dependencyClassification.dependencyEffects)
                .merged(with: ProviderEffects(isAsync: hops, isThrowing: false))

            hasCrossing = hasCrossing || hops || dependencyClassification.hasIsolationCrossing
            isolatedDefault = isolatedDefault || dependencyClassification.usesIsolatedDefaultArgument
            singletons += dependencyClassification.singletonDependencies
            crossDomainSingletons += dependencyClassification.crossDomainSingletonDependencies

            if dependency.isSingleton {
                singletons.append(dependency.typeName)
                if hops {
                    crossDomainSingletons.append(dependency.typeName)
                }
            }

            let call = "\(effects.callPrefix)Zerk<\(parameter.typeName)>.inject()"
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
            crossDomainSingletonDependencies: uniqued(crossDomainSingletons),
            hasIsolationCrossing: hasCrossing,
            usesIsolatedDefaultArgument: isolatedDefault,
            singletonDependencies: uniqued(singletons)
        )
    }

    /// Order-preserving deduplication; the same singleton can be reached
    /// through several paths.
    private func uniqued(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    /// Total effects of building this provider with everything auto-resolved.
    func totalEffects(for resolution: ProviderResolution) -> ProviderEffects {
        resolution.provider.effects.merged(with: classify(resolution).dependencyEffects)
    }

    /// An `@Injectable` value satisfies a parameter when both its key and its
    /// name match — the name match is what keeps two `String` values from
    /// being interchangeable.
    func injectableValue(matching parameter: ParameterRecord) -> InjectableValueRecord? {
        let matches = values.filter { value in
            value.typeKey == parameter.typeKey && value.name == parameter.name
        }
        return matches.count == 1 ? matches[0] : nil
    }
}
