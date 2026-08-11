//
//  CrossModuleGraphTests.swift
//  Zerk
//

import Foundation
import SwiftParser
import Testing
@testable import CodegenToolkit

/// Cross-module stitching against a real package, read from disk.
///
/// `PackageGraphTests` builds its module graphs by hand, which is right for
/// probing the merger's rules but proves nothing about the graphs a real module
/// produces. This resolves `Tests/Fixtures/CrossModule` — two targets, an
/// exported key, an import that finds it, and an import that must not — through
/// the same stages `ZerkCodegen` runs, then merges them.
///
/// It stops short of `swift package zerk graph` itself, which needs a nested
/// build. `CrossModulePackageTests` covers that when `ZERK_E2E` asks for it.
@Suite("Cross-module graph")
struct CrossModuleGraphTests {

    /// The fixture package, found relative to this file so the test does not
    /// depend on a working directory.
    static var fixtureRoot: URL {
        URL(fileURLWithPath: #filePath)          // …/Tests/ZerkInjectionCodegenTests/<this>
            .deletingLastPathComponent()         // …/Tests/ZerkInjectionCodegenTests
            .deletingLastPathComponent()         // …/Tests
            .appendingPathComponent("Fixtures/CrossModule")
    }

    /// Resolves one target of the fixture exactly as the codegen would, and
    /// returns its graph.
    static func graph(forModule module: String) throws -> ZerkGraph {
        let directory = fixtureRoot.appendingPathComponent("Sources/\(module)")
        let sources = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }

        try #require(!sources.isEmpty, "no sources found for \(module) — has the fixture moved?")

        let collector = SourceCollector(settings: .default)
        for source in sources {
            collector.walk(Parser.parse(source: try String(contentsOf: source, encoding: .utf8)),
                           path: source.path)
        }

        let aliases = KeyAliases(declarations: collector.aliasDeclarations,
                                 knownModules: collector.importedModules)
        let rewriter = AliasRewriter(aliases: aliases)
        let gate = GenericGate.admitted(rewriter.rewrite(types: collector.types))
        let resolution = ProviderResolver(
            types: gate.types,
            aliases: aliases,
            keyDisplayNames: rewriter.rewrite(keyDisplayNames: collector.keyDisplayNames)
        ).resolve()
        let imports = ImportedInjectableMerger(
            records: collector.importedInjectables.map {
                var record = $0
                record.typeKey = aliases.representative(for: $0.typeKey)
                return record
            }
        ).merged(
            into: resolution.primaryResolutions,
            localKeys: Set(resolution.resolutions.map(\.injectableKey))
        )
        let values = ImportedValueMerger(
            records: rewriter.rewrite(importedValues: collector.importedValues)
        ).merged(into: rewriter.rewrite(values: collector.values))

        var graph = GraphBuilder(
            values: values.values,
            resolutions: resolution.resolutions,
            primaryResolutions: KeyIndex(imports.primaries),
            keyDisplayNames: rewriter.rewrite(keyDisplayNames: collector.keyDisplayNames)
        ).build()
        graph.module = module
        return graph
    }

    static func merged() throws -> ZerkPackageGraph {
        GraphMerger(graphs: [
            try graph(forModule: "CrossCore"),
            try graph(forModule: "CrossFeature")
        ]).merge()
    }

    // MARK: - The fixture itself

    @Test("the fixture package is where the tests expect it")
    func fixtureExists() throws {
        // A moved or renamed fixture would otherwise show up as a pile of
        // confusing assertion failures rather than one clear one.
        #expect(FileManager.default.fileExists(
            atPath: Self.fixtureRoot.appendingPathComponent("Package.swift").path))
    }

    // MARK: - Per module

    @Test("each module resolves its own keys")
    func modulesResolveIndependently() throws {
        let core = try Self.graph(forModule: "CrossCore")
        let feature = try Self.graph(forModule: "CrossFeature")

        #expect(core.module == "CrossCore")
        #expect(core.keys.map(\.key).sorted() == ["ApiServicing", "InternalOnly"])
        #expect(core.keys.first { $0.key == "ApiServicing" }?.isExported == true)
        #expect(core.keys.first { $0.key == "InternalOnly" }?.isExported == false)

        #expect(feature.module == "CrossFeature")
        #expect(feature.keys.map(\.key).sorted() == ["ApiServicing", "FeedViewModel", "InternalOnly"])
        #expect(feature.keys.first { $0.key == "ApiServicing" }?.isImported == true)
    }

    @Test("a module-qualified dependency is one key with the imported one")
    func qualifiedDependencyFolds() throws {
        let feature = try Self.graph(forModule: "CrossFeature")
        let dependency = feature.keys
            .first { $0.key == "FeedViewModel" }?
            .providers.first?.dependencies.first

        // Written `CrossCore.ApiServicing`, and only one key because
        // `#ZerkImport(module: "CrossCore")` is there.
        #expect(dependency?.source == "injectable")
        #expect(dependency?.key == "ApiServicing")
    }

    // MARK: - Stitched

    @Test("the exported key's import is matched to the module that provides it")
    func resolvesTheImport() throws {
        let merged = try Self.merged()

        #expect(merged.modules.map(\.name) == ["CrossCore", "CrossFeature"])
        let resolved = merged.imports.first { $0.key == "ApiServicing" }
        #expect(resolved?.consumer == "CrossFeature")
        #expect(resolved?.providers == ["CrossCore"])
    }

    @Test("a key that exists elsewhere but is not exported stays unresolved")
    func doesNotMatchUnexportedKeys() throws {
        let merged = try Self.merged()

        // `CrossCore` has `InternalOnly` and does not export it, so its members
        // are internal and no other module could reach them. Matching on the
        // name alone would draw an edge that cannot exist.
        #expect(merged.imports.contains { $0.key == "InternalOnly" } == false)
        #expect(merged.unresolvedImports.map(\.key) == ["InternalOnly"])
        #expect(merged.unresolvedImports.first?.consumer == "CrossFeature")
    }

    @Test("the rendered graph carries the cross-module edge")
    func rendersTheCrossModuleEdge() throws {
        let merged = try Self.merged()
        let mermaid = try GraphRenderer(graph: merged).render(.mermaid)
        let dot = try GraphRenderer(graph: merged).render(.dot)

        #expect(mermaid.contains("subgraph CrossCore"))
        #expect(mermaid.contains("subgraph CrossFeature"))
        // A dashed edge is what crossing a module boundary looks like.
        #expect(mermaid.contains("-.->"))
        #expect(dot.contains("[style=dashed, constraint=false];"))
    }
}
