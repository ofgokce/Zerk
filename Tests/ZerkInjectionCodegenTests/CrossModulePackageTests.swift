//
//  CrossModulePackageTests.swift
//  Zerk
//

import Foundation
import Testing
@testable import CodegenToolkit

/// Runs `swift package zerk graph` against the fixture package for real.
///
/// This is the only test that exercises the parts nothing else can reach: the
/// `ZerkCLI` plugin's target enumeration, its `ZerkCodegen` invocation per
/// target, the handoff to `ZerkGraphTool`, and SwiftPM's own plugin wiring.
/// `CrossModuleGraphTests` covers the same fixture through the library and
/// catches everything downstream of those.
///
/// **Off by default.** It resolves and builds a nested package — about twenty
/// seconds cold against a `swift test` that otherwise finishes in two — so
/// paying it on every run would change how the suite is used. Opt in:
///
/// ```bash
/// ZERK_E2E=1 swift test --filter CrossModulePackageTests
/// ```
///
/// CI should set `ZERK_E2E`, which is the case this test was written for.
@Suite(
    "Cross-module package (end to end)",
    .enabled(if: ProcessInfo.processInfo.environment["ZERK_E2E"] != nil,
             "set ZERK_E2E=1 to run; builds a nested package")
)
struct CrossModulePackageTests {

    static var fixtureRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/CrossModule")
    }

    /// Runs `swift package zerk …` in the fixture and returns what it printed.
    ///
    /// stdout and stderr are captured separately: the graph goes to one and
    /// SwiftPM's build chatter to the other, and mixing them would make the
    /// output unparseable.
    @discardableResult
    static func zerk(_ arguments: [String]) throws -> (status: Int32, out: String, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", "package"] + arguments
        process.currentDirectoryURL = fixtureRoot

        let out = Pipe()
        let error = Pipe()
        process.standardOutput = out
        process.standardError = error
        try process.run()

        // Read before waiting: a full pipe buffer would deadlock otherwise, and
        // the JSON for a real package is comfortably larger than one.
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return (
            process.terminationStatus,
            String(decoding: outData, as: UTF8.self),
            String(decoding: errorData, as: UTF8.self)
        )
    }

    @Test("the CLI enumerates both targets and stitches them")
    func producesTheStitchedGraph() throws {
        let result = try Self.zerk(["zerk", "graph", "--format", "json"])
        try #require(result.status == 0, Comment(rawValue: result.error))

        let graph = try JSONDecoder().decode(
            ZerkPackageGraph.self, from: Data(result.out.utf8))

        // Target enumeration: both, found without being named.
        #expect(graph.modules.map(\.name) == ["CrossCore", "CrossFeature"])

        // And the conclusions `CrossModuleGraphTests` reaches through the
        // library, reached here through the real plugin instead.
        let resolved = graph.imports.first { $0.key == "ApiServicing" }
        #expect(resolved?.consumer == "CrossFeature")
        #expect(resolved?.providers == ["CrossCore"])
        #expect(graph.unresolvedImports.map(\.key) == ["InternalOnly"])
    }

    @Test("--target narrows the run to one module")
    func targetFilterApplies() throws {
        let result = try Self.zerk(["zerk", "graph", "--target", "CrossCore", "--format", "json"])
        try #require(result.status == 0, Comment(rawValue: result.error))

        let graph = try JSONDecoder().decode(
            ZerkPackageGraph.self, from: Data(result.out.utf8))
        #expect(graph.modules.map(\.name) == ["CrossCore"])
        // Nothing to stitch to, so the import simply is not there to resolve.
        #expect(graph.imports.isEmpty)
    }

    @Test("mermaid comes out renderable")
    func rendersMermaid() throws {
        let result = try Self.zerk(["zerk", "graph", "--format", "mermaid"])
        try #require(result.status == 0, Comment(rawValue: result.error))

        #expect(result.out.hasPrefix("graph LR"))
        #expect(result.out.contains("subgraph CrossCore"))
        #expect(result.out.contains("-.->"))
    }

    @Test("--unused reports against the whole package")
    func reportsUnusedKeys() throws {
        let result = try Self.zerk(["zerk", "graph", "--unused"])
        try #require(result.status == 0, Comment(rawValue: result.error))

        // `ApiServicing` is exported and imported by CrossFeature, so it must
        // not appear however the analysis is worded — that crossing is the one
        // thing a per-module view gets wrong.
        #expect(!result.out.contains("ApiServicing"))
        #expect(result.out.contains("InternalOnly") || result.out.contains("No unused keys"))

        // The machine-readable form is the same finding, as a graph.
        let json = try Self.zerk(["zerk", "graph", "--unused", "--format", "json"])
        try #require(json.status == 0, Comment(rawValue: json.error))
        let graph = try JSONDecoder().decode(ZerkPackageGraph.self, from: Data(json.out.utf8))
        #expect(!graph.modules.flatMap { $0.keys.map(\.key) }.contains("ApiServicing"))
    }

    @Test("help works and asks for nothing")
    func printsHelp() throws {
        let bare = try Self.zerk(["zerk"])
        #expect(bare.status == 0)
        #expect(bare.out.contains("Usage: swift package zerk <command>"))

        let graph = try Self.zerk(["zerk", "graph", "--help"])
        #expect(graph.status == 0)
        #expect(graph.out.contains("Usage: swift package zerk graph"))
        #expect(graph.out.contains("--unused"))
    }

    @Test("a bad invocation fails loudly", arguments: [
        ["zerk", "nonsense"],
        ["zerk", "graph", "--bogus", "x"],
        ["zerk", "graph", "--target", "NoSuchTarget"],
        ["zerk", "graph", "--format"]
    ])
    func failuresExitNonZero(arguments: [String]) throws {
        let result = try Self.zerk(arguments)
        // CI depends on this, so it is asserted rather than assumed.
        #expect(result.status != 0)
        #expect(result.error.contains("error:"))
    }
}
