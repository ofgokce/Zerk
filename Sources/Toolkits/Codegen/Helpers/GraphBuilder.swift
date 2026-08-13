//
//  GraphBuilder.swift
//  Zerk
//

import SharedToolkit

/// Turns the resolved graph into ``ZerkGraph``, the artifact written beside the
/// generated Swift.
///
/// Takes the same inputs as `GeneratorOutputBuilder` and reaches the same
/// conclusions through the same helpers — `ParameterClassifier` for what
/// satisfies each parameter, `ProviderResolution.memberName` for what the
/// member is called. That sharing is the point: a graph derived independently
/// could disagree with the code, and a description that disagrees with the thing
/// it describes is worse than none.
///
/// It reports rather than decides. Every diagnostic belongs to the emitter, and
/// this runs after those have been raised — so a module that failed to generate
/// never reaches here.
struct GraphBuilder {
    let values: [InjectableValueRecord]
    let resolutions: [ProviderResolution]
    let primaryResolutions: KeyIndex<ProviderResolution>
    var keyDisplayNames: [String: String] = [:]

    private var classifier: ParameterClassifier {
        ParameterClassifier(values: values, primaryResolutions: primaryResolutions)
    }

    func build() -> ZerkGraph {
        let classifier = self.classifier
        let grouped = Dictionary(grouping: resolutions, by: \.injectableKey)

        // Imported keys have a primary but no resolutions of their own — they
        // are satisfied elsewhere — so they would vanish if the graph were built
        // from `resolutions` alone. A consumer tracing an edge to one needs to
        // find it, marked for what it is.
        let importedKeys = primaryResolutions.values
            .filter { if case .imported = $0.provider { return true } else { return false } }
            .map(\.injectableKey)

        var keys: [ZerkGraph.Key] = []

        for key in Set(grouped.keys).union(importedKeys).sorted() {
            let providers = (grouped[key] ?? [])
                .sorted { ($0.memberName, $0.provider.location) < ($1.memberName, $1.provider.location) }
            let isImported = importedKeys.contains(key) && providers.isEmpty

            keys.append(
                ZerkGraph.Key(
                    key: key,
                    displayName: keyDisplayNames[key] ?? key,
                    isExported: providers.contains(where: \.isExported),
                    isImported: isImported,
                    isGeneric: KeyShape.isShape(key),
                    primaryMember: isImported ? nil : primaryResolutions[key]?.memberName,
                    providers: providers.map { provider(for: $0, classifier: classifier) }
                )
            )
        }

        return ZerkGraph(
            keys: keys,
            values: values
                .sorted { ($0.typeKey, $0.name) < ($1.typeKey, $1.name) }
                .map(value(for:))
        )
    }

    private func provider(for resolution: ProviderResolution,
                          classifier: ParameterClassifier) -> ZerkGraph.Provider {
        let classification = classifier.classify(resolution)
        let effects = resolution.provider.effects

        return ZerkGraph.Provider(
            typeName: resolution.typeName,
            memberName: resolution.memberName,
            kind: kind(of: resolution),
            lifetime: resolution.isSingleton ? "singleton"
                : resolution.scope == nil ? "transient" : "scoped",
            scope: resolution.scope?.identity,
            isolation: resolution.isolation.actorName,
            isAsync: effects.isAsync,
            isThrowing: effects.isThrowing,
            isPrimary: primaryResolutions[resolution.injectableKey]?.provider.location
                == resolution.provider.location,
            location: location(resolution.provider.location),
            condition: resolution.condition.guardText,
            dependencies: classification.parameters.map {
                dependency(for: $0, classifier: classifier)
            }
        )
    }

    /// What a consumer would call this provider in prose, and what Zerk's own
    /// diagnostics call it.
    private func kind(of resolution: ProviderResolution) -> String {
        switch resolution.provider {
        case .implicit:
            return "initializer"
        case .imported:
            return "imported"
        case .explicit(let provider):
            switch provider.kind {
            case .initializer:
                return "initializer"
            case .declaration:
                return "declaration"
            default:
                return "factory"
            }
        }
    }

    /// Reads the *binding the emitter chose*, then names what it chose. Deciding
    /// independently here would let the graph claim a dependency the generated
    /// code does not actually resolve — the one failure mode this artifact
    /// cannot afford.
    private func dependency(for classified: ClassifiedParameter,
                            classifier: ParameterClassifier) -> ZerkGraph.Dependency {
        let parameter = classified.parameter

        guard classified.binding != .external else {
            return ZerkGraph.Dependency(
                parameterName: parameter.name,
                typeName: parameter.typeName,
                source: "caller",
                key: nil,
                valueName: nil
            )
        }

        if let value = classifier.injectableValue(matching: parameter) {
            return ZerkGraph.Dependency(
                parameterName: parameter.name,
                typeName: parameter.typeName,
                source: "value",
                key: value.typeKey,
                valueName: value.name
            )
        }

        return ZerkGraph.Dependency(
            parameterName: parameter.name,
            typeName: parameter.typeName,
            source: "injectable",
            key: primaryResolutions[parameter]?.injectableKey ?? parameter.typeKey,
            valueName: nil
        )
    }

    private func value(for record: InjectableValueRecord) -> ZerkGraph.Value {
        ZerkGraph.Value(
            name: record.name,
            key: record.typeKey,
            displayName: record.keyText,
            isExported: record.isExported,
            isImported: record.isImported,
            injectionMethod: record.injectionMethod.rawValue,
            isolation: record.isolation.actorName,
            isAsync: record.effects.isAsync,
            isThrowing: record.effects.isThrowing,
            location: location(record.location),
            condition: record.condition.guardText
        )
    }

    private func location(_ location: AttributeLocation) -> ZerkGraph.Location {
        ZerkGraph.Location(
            file: location.filePath,
            line: location.line,
            column: location.column
        )
    }
}
