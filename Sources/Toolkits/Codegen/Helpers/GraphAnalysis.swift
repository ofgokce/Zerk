//
//  GraphAnalysis.swift
//  Zerk
//

/// Questions answered by reading a resolved package graph.
///
/// Today there is one: which registrations is nothing asking for. It is worth
/// stating why that question needs the *package* graph rather than a module's.
/// A key registered in one module and resolved only from another looks unused
/// from inside either one — the declaring module sees no local consumer, and the
/// consuming module sees no registration. Only the joined view has both halves.
///
/// Like everything else downstream of `GraphMerger`, this is presentation: it
/// reports, it never resolves, and no build depends on it.
struct GraphAnalysis {

    let graph: ZerkPackageGraph

    /// One registration nothing in the package resolves.
    struct UnusedKey {
        let module: String
        let key: ZerkGraph.Key
    }

    /// Registrations no provider depends on and no `@Injected` asks for.
    ///
    /// Four things disqualify a key, and each is a different sense of "used":
    ///
    /// - **an incoming edge from any module.** Matched by canonical key across
    ///   the whole package, which is what makes cross-module use count: the
    ///   consumer's own graph records the edge, and the merge puts the two in
    ///   one room.
    /// - **a direct resolution** — an `@Injected` property or an `@injected`
    ///   parameter. These are not edges: nothing in the graph *provides* them,
    ///   which is exactly why ``ZerkGraph/Key/directResolutions`` exists.
    /// - **being imported.** An `@ImportedInjectable` is a reference to another
    ///   module's registration, not a registration of its own; reporting it
    ///   would name a declaration in a module that does not contain it.
    /// - **being exported.** `@Injectable(public: true)` is a promise to
    ///   consumers this package cannot see, so an unused public key is the
    ///   normal state of a library's surface rather than a finding. Reporting
    ///   those would bury the real ones.
    ///
    /// Sorted by module then key, so two runs over unchanged sources agree.
    func unusedKeys() -> [UnusedKey] {
        let resolved = resolvedKeys()

        return graph.modules
            .flatMap { module in
                module.keys
                    .filter { key in
                        !key.isImported
                            && !key.isExported
                            && key.directResolutions == 0
                            && !resolved.contains(key.key)
                    }
                    .map { UnusedKey(module: module.name, key: $0) }
            }
            .sorted { ($0.module, $0.key.key) < ($1.module, $1.key.key) }
    }

    /// Every key some provider in the package depends on.
    ///
    /// Deliberately *not* restricted to the module the edge was found in. Keys
    /// are canonical, so an edge to `Logging` in one module and a registration
    /// of `Logging` in another are the same key — which is the case this whole
    /// analysis exists to get right.
    private func resolvedKeys() -> Set<String> {
        var keys: Set<String> = []
        for module in graph.modules {
            for key in module.keys {
                for provider in key.providers {
                    for dependency in provider.dependencies {
                        if let target = dependency.key {
                            keys.insert(target)
                        }
                    }
                }
            }
        }
        return keys
    }

    /// The same package graph narrowed to the unused keys, so every existing
    /// renderer can show them.
    ///
    /// Values are dropped rather than filtered. Zerk records which *key* an
    /// `@Injected(\.member)` resolves but not which member, so a value reached
    /// that way is indistinguishable from a dead one — and a report that cries
    /// wolf is one people learn to skip. Keys do not have that problem, because
    /// a key path still names the key it resolves.
    ///
    /// Imports go too: an unused key by definition has nothing importing it, so
    /// carrying the package's import edges into this view would draw lines to
    /// nodes that are no longer there.
    func unusedGraph() -> ZerkPackageGraph {
        let unused = Dictionary(grouping: unusedKeys(), by: \.module)

        return ZerkPackageGraph(
            modules: graph.modules.compactMap { module in
                guard let keys = unused[module.name] else {
                    return nil
                }
                return ZerkPackageGraph.Module(
                    name: module.name,
                    keys: keys.map(\.key),
                    values: []
                )
            },
            imports: [],
            unresolvedImports: []
        )
    }
}
