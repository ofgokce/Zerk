//
//  BubbleResolver.swift
//  Zerk
//

/// Folds the requirements bubbled up by a member's resolved dependencies into
/// one parameter list, and works out what each dependency is called with.
///
/// When Zerk resolves a dependency whose own provider still needs arguments,
/// those arguments have to come from somewhere, so they surface on whatever is
/// doing the resolving. Several dependencies asking for overlapping things is
/// the normal case, and every rule here is about not declaring one thing twice:
///
/// - a requirement the member already declares is **shared** — but only when
///   that parameter is marked `@injectable`, so sharing is always written down
///   rather than happening by coincidence of naming;
/// - requirements agreeing on name *and* type are one parameter, however many
///   dependencies asked;
/// - requirements agreeing on name but **not** type keep the label they were
///   declared with and take distinct inner names, since a signature cannot
///   declare one name twice — `inject(value valueA: ValueA, value valueB: ValueB)`.
///
/// Shared by both resolution paths: `inject()` on the provider side and the
/// generated overload on the `@injected` side. They differ in what they emit,
/// not in how requirements combine, and duplicating this is how the two would
/// drift apart.
struct BubbleResolver {

    /// One dependency's requirements, tagged with the parameter that pulled them
    /// in. That name is what disambiguates a clash, so it travels with them.
    struct Request {
        let sourceName: String
        let requirements: [ParameterRecord]
    }

    /// A bubbled requirement landing on a name the member already uses, where
    /// sharing was not asked for.
    struct Collision {
        let dependencyName: String
        let requirement: ParameterRecord
        let own: ParameterRecord
    }

    struct Resolution {
        /// Bubbled parameters, in the order their sources appear. Callers append
        /// these after the member's own parameters.
        let parameters: [ParameterRecord]
        /// Source parameter name -> the arguments to call its dependency with.
        let arguments: [String: [String]]
        let collisions: [Collision]
    }

    /// - Parameters:
    ///   - requests: one per dependency being resolved, in declaration order.
    ///   - ownExternals: the member's own caller-supplied parameters, keyed by
    ///     ``ParameterRecord/resolutionIdentity``.
    static func resolve(_ requests: [Request],
                        ownExternals: [String: ParameterRecord]) -> Resolution {
        /// Where one requirement's value comes from once everything is placed.
        enum Binding {
            case own(String)
            case bubbled(Int)
        }

        var placed: [ParameterRecord] = []
        var indexByIdentity: [String: Int] = [:]
        var sourceByIndex: [Int: String] = [:]
        var collisions: [Collision] = []
        var bindings: [(source: String, items: [(ParameterRecord, Binding?)])] = []

        for request in requests {
            var items: [(ParameterRecord, Binding?)] = []

            for requirement in request.requirements {
                if let own = ownExternals[requirement.resolutionIdentity] {
                    guard own.feedsDependencies else {
                        collisions.append(Collision(
                            dependencyName: request.sourceName,
                            requirement: requirement,
                            own: own
                        ))
                        items.append((requirement, nil))
                        continue
                    }
                    items.append((requirement, .own(own.name)))
                    continue
                }

                // Same name *and* type as something already bubbled: one
                // parameter serves both dependencies.
                if let existing = indexByIdentity[requirement.resolutionIdentity] {
                    items.append((requirement, .bubbled(existing)))
                    continue
                }

                let index = placed.count
                placed.append(requirement)
                indexByIdentity[requirement.resolutionIdentity] = index
                sourceByIndex[index] = request.sourceName
                items.append((requirement, .bubbled(index)))
            }

            bindings.append((request.sourceName, items))
        }

        let finalNames = disambiguate(placed, sources: sourceByIndex, reserved: ownExternals)

        var parameters: [ParameterRecord] = []
        for index in placed.indices {
            var parameter = placed[index]
            parameter.name = finalNames[index]
            parameters.append(parameter)
        }

        var arguments: [String: [String]] = [:]
        for (source, items) in bindings {
            arguments[source] = items.compactMap { requirement, binding in
                guard let binding else {
                    return nil
                }
                let inner: String
                switch binding {
                case .own(let name):
                    inner = name
                case .bubbled(let index):
                    inner = finalNames[index]
                }
                // The *requirement's* label, since that is what the dependency's
                // own signature declares; only the inner name is ours to choose.
                return requirement.label.map { "\($0): \(inner)" } ?? inner
            }
        }

        return Resolution(parameters: parameters, arguments: arguments, collisions: collisions)
    }

    /// Final inner names, renaming only where a name would otherwise repeat.
    ///
    /// A name repeats either because two requirements share it with different
    /// types, or because the member already declares it for something else. Both
    /// are the same problem — a signature cannot bind one name twice — so both
    /// take the same fix: suffix with the parameter that pulled the requirement
    /// in, and number it if even that is taken.
    private static func disambiguate(_ placed: [ParameterRecord],
                                     sources: [Int: String],
                                     reserved: [String: ParameterRecord]) -> [String] {
        var taken = Set(reserved.values.map(\.name))
        var counts: [String: Int] = [:]
        for parameter in placed {
            counts[parameter.name, default: 0] += 1
        }

        var finalNames: [String] = []
        for index in placed.indices {
            let base = placed[index].name
            guard counts[base, default: 0] > 1 || taken.contains(base) else {
                taken.insert(base)
                finalNames.append(base)
                continue
            }

            let source = sources[index] ?? ""
            var candidate = base + source.upperCamelCased
            var suffix = 2
            while candidate == base || taken.contains(candidate) {
                candidate = "\(base)\(source.upperCamelCased)\(suffix)"
                suffix += 1
            }
            taken.insert(candidate)
            finalNames.append(candidate)
        }

        return finalNames
    }
}
