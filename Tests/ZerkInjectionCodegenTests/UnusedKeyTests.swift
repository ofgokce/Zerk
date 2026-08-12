//
//  UnusedKeyTests.swift
//  Zerk
//

import Foundation
import Testing
@testable import CodegenToolkit

/// `swift package zerk graph --unused`: which registrations nothing asks for.
///
/// The analysis is only worth having if it is quiet — a report that names keys
/// the app genuinely uses is one people stop reading. So most of these tests
/// assert what is *not* reported: a key reached only from another module, only
/// from `@Injected`, only from an `@injected` parameter, or exported for
/// consumers this package cannot see.
@Suite("Unused keys")
struct UnusedKeyTests {

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
                            directResolutions: Int = 0,
                            providers: [ZerkGraph.Provider] = []) -> ZerkGraph.Key {
        ZerkGraph.Key(
            key: name,
            displayName: name,
            isExported: exported,
            isImported: imported,
            isGeneric: false,
            primaryMember: providers.first?.memberName,
            directResolutions: directResolutions,
            providers: providers
        )
    }

    private static func analysis(_ graphs: [ZerkGraph]) -> GraphAnalysis {
        GraphAnalysis(graph: GraphMerger(graphs: graphs).merge())
    }

    // MARK: - What is reported

    @Test("a key nothing depends on and nothing injects is reported")
    func reportsAnOrphan() {
        let unused = Self.analysis([
            ZerkGraph(module: "App", keys: [
                Self.key("Logging", providers: [Self.provider("Logger")]),
                Self.key("Root", directResolutions: 1,
                         providers: [Self.provider("Root", dependsOn: ["Logging"])]),
                Self.key("Analytics", providers: [Self.provider("AnalyticsClient")])
            ], values: [])
        ]).unusedKeys()

        #expect(unused.map(\.key.key) == ["Analytics"])
        #expect(unused.first?.module == "App")
    }

    @Test("the report is sorted by module then key")
    func reportIsDeterministic() {
        let unused = Self.analysis([
            ZerkGraph(module: "Feature", keys: [Self.key("Zeta"), Self.key("Alpha")], values: []),
            ZerkGraph(module: "Core", keys: [Self.key("Beta")], values: [])
        ]).unusedKeys()

        #expect(unused.map { "\($0.module).\($0.key.key)" } == ["Core.Beta", "Feature.Alpha", "Feature.Zeta"])
    }

    // MARK: - What is not reported

    /// The case that needs the whole package: the registration is in one module
    /// and the only consumer is in another, so each module alone would call it
    /// unused.
    @Test("a key resolved only from another module is not reported")
    func crossModuleUseCounts() {
        let unused = Self.analysis([
            ZerkGraph(module: "Core", keys: [
                Self.key("Api", exported: true, providers: [Self.provider("ApiService")]),
                Self.key("Internal", providers: [Self.provider("InternalThing")])
            ], values: []),
            ZerkGraph(module: "Feature", keys: [
                Self.key("Api", imported: true),
                Self.key("Feed", directResolutions: 1,
                         providers: [Self.provider("Feed", dependsOn: ["Api"])])
            ], values: [])
        ]).unusedKeys()

        // `Api` is used across the boundary; `Internal` genuinely is not.
        #expect(unused.map(\.key.key) == ["Internal"])
    }

    /// A root — the thing the app itself asks for — has no incoming edge by
    /// definition. Without `directResolutions` every one of them would be
    /// reported, which would make the whole report useless.
    @Test("a key reached only by @Injected is not reported")
    func directResolutionCounts() {
        let unused = Self.analysis([
            ZerkGraph(module: "App", keys: [
                Self.key("Root", directResolutions: 1, providers: [Self.provider("Root")])
            ], values: [])
        ]).unusedKeys()

        #expect(unused.isEmpty)
    }

    @Test("an exported key is not reported")
    func exportedKeysAreExcluded() {
        let unused = Self.analysis([
            ZerkGraph(module: "Core", keys: [
                Self.key("PublicApi", exported: true, providers: [Self.provider("ApiService")])
            ], values: [])
        ]).unusedKeys()

        // Its consumers are outside the package, where Zerk cannot see them —
        // so "nothing here resolves it" is the normal state of a library's
        // surface rather than a finding.
        #expect(unused.isEmpty)
    }

    @Test("an imported key is not reported")
    func importedKeysAreExcluded() {
        let unused = Self.analysis([
            ZerkGraph(module: "Feature", keys: [Self.key("Elsewhere", imported: true)], values: [])
        ]).unusedKeys()

        // It is a reference to another module's registration, so reporting it
        // would name a declaration this module does not contain.
        #expect(unused.isEmpty)
    }

    // MARK: - The filtered graph

    @Test("the filtered graph keeps only the unused keys, and only their modules")
    func filteredGraphIsNarrowed() {
        let graph = Self.analysis([
            ZerkGraph(module: "Core", keys: [
                Self.key("Used", directResolutions: 1, providers: [Self.provider("Thing")])
            ], values: []),
            ZerkGraph(module: "Feature", keys: [
                Self.key("Orphan", providers: [Self.provider("Orphan")])
            ], values: [])
        ]).unusedGraph()

        #expect(graph.modules.map(\.name) == ["Feature"])
        #expect(graph.modules.first?.keys.map(\.key) == ["Orphan"])
        // Values are dropped rather than filtered — see `unusedGraph()` for why
        // a value cannot be judged with the data the graph records.
        #expect(graph.modules.first?.values.isEmpty == true)
        #expect(graph.imports.isEmpty)
    }

    @Test("the filtered graph renders in every format")
    func filteredGraphRenders() throws {
        let graph = Self.analysis([
            ZerkGraph(module: "App", keys: [Self.key("Orphan", providers: [Self.provider("Orphan")])],
                      values: [])
        ]).unusedGraph()

        for format in GraphRenderer.Format.allCases {
            let rendered = try GraphRenderer(graph: graph).render(format)
            #expect(rendered.contains("Orphan"), "\(format.rawValue): \(rendered)")
        }
    }

    // MARK: - End to end, from real source

    @Test("direct resolutions are counted from real source")
    func countsUsesFromSource() throws {
        let graph = CompileFixture.graph(source: """
        protocol Logging {}
        protocol Analytics {}

        @Injectable<Logging>
        struct Logger: Logging {}

        @Injectable<Analytics>
        struct AnalyticsClient: Analytics {}

        @Injectable
        struct Root {
            let logging: Logging
        }

        final class Screen {
            @Injected var root: Root
        }
        """)

        let root = try #require(graph.keys.first { $0.key == "Root" })
        #expect(root.directResolutions == 1)

        let logging = try #require(graph.keys.first { $0.key == "Logging" })
        #expect(logging.directResolutions == 0)

        // `Logging` is still used — by `Root`'s provider — so only `Analytics`
        // is left over.
        var moduleGraph = graph
        moduleGraph.module = "App"
        let unused = GraphAnalysis(graph: GraphMerger(graphs: [moduleGraph]).merge()).unusedKeys()
        #expect(unused.map(\.key.key) == ["Analytics"])
    }

    @Test("an @injected parameter counts as a resolution")
    func markedParametersCount() throws {
        let graph = CompileFixture.graph(source: """
        protocol Logging {}

        @Injectable<Logging>
        struct Logger: Logging {}

        struct Screen {
            init(@injected logging: Logging) {}
        }
        """)

        let logging = try #require(graph.keys.first { $0.key == "Logging" })
        #expect(logging.directResolutions == 1)
    }

    // MARK: - Through GraphExport, the way the CLI reaches it

    /// Writes graphs to disk and runs the export the command plugin runs.
    private static func export(_ graphs: [ZerkGraph],
                               format: String,
                               unusedOnly: Bool) throws -> String {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("zerk-unused-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var paths: [String] = []
        for graph in graphs {
            let url = directory.appendingPathComponent("\(graph.module ?? "M").graph.json")
            try graph.encoded().write(to: url)
            paths.append(url.path)
        }

        return try GraphExport(inputPaths: paths, format: format, unusedOnly: unusedOnly).run() ?? ""
    }

    @Test("the text report names the count and where to look")
    func textReportReads() throws {
        let rendered = try Self.export(
            [ZerkGraph(module: "App", keys: [
                Self.key("Analytics", providers: [Self.provider("AnalyticsClient")])
            ], values: [])],
            format: "text",
            unusedOnly: true
        )

        #expect(rendered.hasPrefix("1 key is registered but resolved by nothing:"))
        #expect(rendered.contains("App"))
        #expect(rendered.contains("Analytics"))
        #expect(rendered.contains("AnalyticsClient"))
        #expect(rendered.contains("F.swift:1"))
    }

    /// A blank page is a bad way to say "nothing to report" — it reads the same
    /// as a broken command.
    @Test("nothing unused says so")
    func emptyReportSaysSo() throws {
        let rendered = try Self.export(
            [ZerkGraph(module: "App", keys: [
                Self.key("Root", directResolutions: 1, providers: [Self.provider("Root")])
            ], values: [])],
            format: "text",
            unusedOnly: true
        )

        #expect(rendered == "No unused keys: every registration is resolved by something.")
    }

    @Test("json stays machine-readable, with no prose in it")
    func jsonReportIsPlainGraph() throws {
        let rendered = try Self.export(
            [ZerkGraph(module: "App", keys: [
                Self.key("Analytics", providers: [Self.provider("AnalyticsClient")])
            ], values: [])],
            format: "json",
            unusedOnly: true
        )

        let graph = try JSONDecoder().decode(ZerkPackageGraph.self, from: Data(rendered.utf8))
        #expect(graph.modules.flatMap { $0.keys.map(\.key) } == ["Analytics"])
    }

    /// A generic registration is filed under its key *shape*, so a use spelled
    /// with a concrete specialization has to be mapped through the same index
    /// the emitter uses — counting the spelling would credit a key that does
    /// not exist.
    @Test("a use of a generic key is counted against its shape")
    func genericUsesAreCountedAgainstTheShape() throws {
        let graph = CompileFixture.graph(source: """
        @Injectable
        struct Cache<Element> {
            init() {}
        }

        final class Screen {
            @Injected var cache: Cache<String>
        }
        """)

        let shape = try #require(graph.keys.first { $0.isGeneric })
        #expect(shape.directResolutions == 1)
    }
}
