//
//  PackageGraphTests.swift
//  Zerk
//

import Foundation
import Testing
@testable import CodegenToolkit

/// Joining per-module graphs, and drawing the result.
///
/// The graphs here are built by hand rather than through the codegen, because
/// what is under test is the *stitching* — a module-boundary question that a
/// single-module fixture cannot pose. `GraphArtifactTests` covers the per-module
/// half against real source.
@Suite("Package graph")
struct PackageGraphTests {

    // MARK: - Fixtures

    private static let location = ZerkGraph.Location(file: "F.swift", line: 1, column: 1)

    private static func provider(_ type: String, dependsOn: [String] = []) -> ZerkGraph.Provider {
        ZerkGraph.Provider(
            typeName: type,
            memberName: type.lowercased(),
            kind: "initializer",
            lifetime: "transient",
            scope: nil,
            isolation: nil,
            isAsync: false,
            isThrowing: false,
            isPrimary: true,
            location: location,
            dependencies: dependsOn.map {
                ZerkGraph.Dependency(
                    parameterName: $0.lowercased(),
                    typeName: $0,
                    source: "injectable",
                    key: $0,
                    valueName: nil
                )
            }
        )
    }

    private static func key(_ name: String,
                            exported: Bool = false,
                            imported: Bool = false,
                            providers: [ZerkGraph.Provider] = []) -> ZerkGraph.Key {
        ZerkGraph.Key(
            key: name,
            displayName: name,
            isExported: exported,
            isImported: imported,
            isGeneric: false,
            primaryMember: providers.first?.memberName,
            providers: providers
        )
    }

    private static func graph(_ module: String?, _ keys: [ZerkGraph.Key]) -> ZerkGraph {
        ZerkGraph(module: module, keys: keys, values: [])
    }

    /// `Core` exports `Api`; `Feature` imports it and builds `Feed` on top.
    private static var twoModules: [ZerkGraph] {
        [
            graph("Core", [key("Api", exported: true, providers: [provider("ApiService")])]),
            graph("Feature", [
                key("Api", imported: true),
                key("Feed", providers: [provider("Feed", dependsOn: ["Api"])])
            ])
        ]
    }

    // MARK: - Stitching

    @Test("an import is matched to the module that exports it")
    func matchesImportsToExporters() {
        let merged = GraphMerger(graphs: Self.twoModules).merge()

        #expect(merged.modules.map(\.name) == ["Core", "Feature"])
        #expect(merged.imports.count == 1)
        #expect(merged.imports.first?.key == "Api")
        #expect(merged.imports.first?.consumer == "Feature")
        #expect(merged.imports.first?.providers == ["Core"])
        #expect(merged.unresolvedImports.isEmpty)
    }

    @Test("an import nothing exports is reported, not dropped")
    func reportsUnresolvedImports() {
        let graphs = [
            Self.graph("Core", [Self.key("Api", exported: true, providers: [Self.provider("ApiService")])]),
            Self.graph("Feature", [Self.key("Elsewhere", imported: true)])
        ]
        let merged = GraphMerger(graphs: graphs).merge()

        // Usually benign — the key lives in another package — but the only way
        // a genuine mistake surfaces is if unmatched imports are shown.
        #expect(merged.imports.isEmpty)
        #expect(merged.unresolvedImports.map(\.key) == ["Elsewhere"])
        #expect(merged.unresolvedImports.first?.consumer == "Feature")
    }

    @Test("a key that exists but is not exported does not answer an import")
    func requiresExportToMatch() {
        let graphs = [
            // Not exported: its generated members are internal, so no other
            // module could reach them however much the names line up.
            Self.graph("Core", [Self.key("Api", exported: false, providers: [Self.provider("ApiService")])]),
            Self.graph("Feature", [Self.key("Api", imported: true)])
        ]
        let merged = GraphMerger(graphs: graphs).merge()

        #expect(merged.imports.isEmpty)
        #expect(merged.unresolvedImports.map(\.key) == ["Api"])
    }

    @Test("two exporters of one key are both reported")
    func recordsAmbiguousExporters() {
        let graphs = [
            Self.graph("A", [Self.key("Api", exported: true, providers: [Self.provider("AApi")])]),
            Self.graph("B", [Self.key("Api", exported: true, providers: [Self.provider("BApi")])]),
            Self.graph("Feature", [Self.key("Api", imported: true)])
        ]
        let merged = GraphMerger(graphs: graphs).merge()

        // Which one the consumer imported is decided by its `import`
        // statements, which Zerk never sees — so both are shown rather than one
        // silently picked.
        #expect(merged.imports.first?.providers == ["A", "B"])
    }

    @Test("a module's own exports do not answer its own imports")
    func aModuleIsNotItsOwnProvider() {
        // Not a special case in the merger, and deliberately not guarded there:
        // a module contributes one entry per key, and that entry is either
        // imported or provided. This pins the invariant the merger leans on.
        let merged = GraphMerger(graphs: [
            Self.graph("Core", [
                Self.key("Api", exported: true, providers: [Self.provider("ApiService")]),
                Self.key("Other", imported: true)
            ])
        ]).merge()

        #expect(merged.imports.isEmpty)
        #expect(merged.unresolvedImports.map(\.key) == ["Other"])
    }

    @Test("a graph with no module name is skipped rather than mis-attributed")
    func skipsUnnamedGraphs() {
        let merged = GraphMerger(graphs: [Self.graph(nil, [Self.key("Api")])]).merge()
        #expect(merged.modules.isEmpty)
    }

    @Test("merging is deterministic")
    func mergingIsDeterministic() throws {
        let forwards = try GraphMerger(graphs: Self.twoModules).merge().encoded()
        let backwards = try GraphMerger(graphs: Self.twoModules.reversed()).merge().encoded()
        // Input order is whatever order the plugin walked the targets in.
        #expect(forwards == backwards)
    }

    // MARK: - Rendering

    @Test("DOT clusters by module and dashes the cross-module edge")
    func rendersDot() throws {
        let merged = GraphMerger(graphs: Self.twoModules).merge()
        let dot = try GraphRenderer(graph: merged).render(.dot)

        #expect(dot.hasPrefix("digraph Zerk {"))
        #expect(dot.contains("label=\"Core\";"))
        #expect(dot.contains("label=\"Feature\";"))
        // Feed -> Api inside Feature, solid.
        #expect(dot.contains("m1k1 -> m1k0;"))
        // Feature's Api -> Core's Api, dashed. This edge is the whole point.
        #expect(dot.contains("m1k0 -> m0k0 [style=dashed, constraint=false];"))
    }

    @Test("Mermaid does the same with its own syntax")
    func rendersMermaid() throws {
        let merged = GraphMerger(graphs: Self.twoModules).merge()
        let mermaid = try GraphRenderer(graph: merged).render(.mermaid)

        #expect(mermaid.hasPrefix("graph LR"))
        // Quoted and given a positional identifier, so a title needing escaping
        // survives the parser.
        #expect(mermaid.contains("subgraph cluster0[\"Core\"]"))
        #expect(mermaid.contains("m1k1 --> m1k0"))
        #expect(mermaid.contains("m1k0 -.-> m0k0"))
    }

    @Test("labels carry the lifetime, and only when there is one worth naming")
    func labelsLifetimes() throws {
        var singleton = Self.provider("Clock")
        singleton = ZerkGraph.Provider(
            typeName: "Clock", memberName: "clock", kind: "initializer",
            lifetime: "singleton", scope: nil, isolation: nil,
            isAsync: false, isThrowing: false, isPrimary: true,
            location: Self.location, dependencies: []
        )
        let scoped = ZerkGraph.Provider(
            typeName: "Cache", memberName: "cache", kind: "initializer",
            lifetime: "scoped", scope: "session", isolation: nil,
            isAsync: false, isThrowing: false, isPrimary: true,
            location: Self.location, dependencies: []
        )
        let merged = GraphMerger(graphs: [
            Self.graph("M", [
                Self.key("Clock", providers: [singleton]),
                Self.key("Cache", providers: [scoped]),
                Self.key("Plain", providers: [Self.provider("Plain")])
            ])
        ]).merge()

        let dot = try GraphRenderer(graph: merged).render(.dot)
        #expect(dot.contains("Clock\\nsingleton"))
        #expect(dot.contains("Cache\\nscoped(.session)"))
        // Transient is the default and labelling every node with it would say
        // nothing, so it is left off.
        #expect(dot.contains("label=\"Plain\"]"))
    }

    @Test("key names hostile to each format are escaped")
    func escapesLabels() throws {
        let merged = GraphMerger(graphs: [
            Self.graph("M", [Self.key("Cache<String>", providers: [Self.provider("Cache")])])
        ]).merge()

        // `<` would end a Mermaid label early and corrupt the rest of the
        // diagram; DOT is fine with it inside quotes.
        #expect(try GraphRenderer(graph: merged).render(.mermaid).contains("Cache#lt;String#gt;"))
        #expect(try GraphRenderer(graph: merged).render(.dot).contains("Cache<String>"))
    }

    @Test("an edge to a key the module does not have is dropped, not emitted broken")
    func skipsDanglingEdges() throws {
        // A dependency on a key with no entry — possible when a provider's
        // parameter resolves to something the module never registered.
        let merged = GraphMerger(graphs: [
            Self.graph("M", [Self.key("Feed", providers: [Self.provider("Feed", dependsOn: ["Missing"])])])
        ]).merge()

        let dot = try GraphRenderer(graph: merged).render(.dot)
        #expect(!dot.contains("->"), "an edge with no target node would be invalid output")
    }

    // MARK: - The export facade

    @Test("GraphExport reads files, renders, and can write to disk")
    func exportRoundTrip() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("zerk-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var paths: [String] = []
        for graph in Self.twoModules {
            let url = directory.appendingPathComponent("\(graph.module!).json")
            try graph.encoded().write(to: url)
            paths.append(url.path)
        }

        let rendered = try GraphExport(inputPaths: paths, format: "mermaid").run()
        #expect(rendered?.contains("m1k0 -.-> m0k0") == true)

        let output = directory.appendingPathComponent("graph.dot")
        let returned = try GraphExport(
            inputPaths: paths, format: "dot", outputPath: output.path
        ).run()
        #expect(returned == nil, "writing to a file should not also return the text")
        #expect(try String(contentsOf: output, encoding: .utf8).hasPrefix("digraph Zerk {"))
    }

    @Test("GraphExport reports an unknown format and an unreadable file by name")
    func exportReportsFailures() throws {
        #expect(throws: GraphExport.Failure.self) {
            try GraphExport(inputPaths: ["/nonexistent.json"], format: "json").run()
        }
        #expect(throws: GraphExport.Failure.self) {
            try GraphExport(inputPaths: ["/nonexistent.json"], format: "svg").run()
        }
    }
}
