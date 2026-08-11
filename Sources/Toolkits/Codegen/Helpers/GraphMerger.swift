//
//  GraphMerger.swift
//  Zerk
//

/// Joins per-module graphs into a ``ZerkPackageGraph``, matching each import to
/// the module that exports it.
///
/// The matching rule is the one the compiler already enforces, restated: a key
/// crosses a module boundary only when it is **exported** — `@Injectable(public:
/// true)` — because that is what makes its generated members `public`. An import
/// that finds only a non-exported key of the same name has not found its answer,
/// and is reported unresolved rather than matched optimistically.
struct GraphMerger {

    /// Per-module graphs. A graph with no `module` name is skipped: it cannot be
    /// placed, and guessing would attribute someone's keys to the wrong module.
    let graphs: [ZerkGraph]

    func merge() -> ZerkPackageGraph {
        let named = graphs
            .compactMap { graph -> (name: String, graph: ZerkGraph)? in
                graph.module.map { (name: $0, graph: graph) }
            }
            .sorted { $0.name < $1.name }

        // Which modules export each key, built once — the matching below is
        // otherwise quadratic in the number of modules.
        var exporters: [String: [String]] = [:]
        for module in named {
            for key in module.graph.keys where key.isExported && !key.isImported && !key.providers.isEmpty {
                exporters[key.key, default: []].append(module.name)
            }
        }

        var imports: [ZerkPackageGraph.ResolvedImport] = []
        var unresolved: [ZerkPackageGraph.UnresolvedImport] = []

        for module in named {
            for key in module.graph.keys where key.isImported {
                // No need to exclude the consumer itself. `exporters` is built
                // from keys that are *not* imported, this loop visits only ones
                // that are, and a module contributes exactly one entry per key —
                // so a module can never appear as its own provider. Upstream,
                // `ImportedInjectableMerger` makes "imported and declared here"
                // a build error, so the shape never reaches a graph either.
                let providers = (exporters[key.key] ?? []).sorted()

                if providers.isEmpty {
                    unresolved.append(
                        ZerkPackageGraph.UnresolvedImport(key: key.key, consumer: module.name)
                    )
                } else {
                    imports.append(
                        ZerkPackageGraph.ResolvedImport(
                            key: key.key,
                            consumer: module.name,
                            providers: providers
                        )
                    )
                }
            }
        }

        return ZerkPackageGraph(
            modules: named.map {
                ZerkPackageGraph.Module(name: $0.name, keys: $0.graph.keys, values: $0.graph.values)
            },
            // Sorted for the same reason everything else is: this is written to
            // a file people diff.
            imports: imports.sorted { ($0.consumer, $0.key) < ($1.consumer, $1.key) },
            unresolvedImports: unresolved.sorted { ($0.consumer, $0.key) < ($1.consumer, $1.key) }
        )
    }
}
