//
//  ZerkGraphPlugin.swift
//  Zerk
//

import PackagePlugin
import Foundation
#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin
#endif

/// `swift package zerk-graph` — the resolved dependency graph for every target,
/// joined across module boundaries, rendered where you ask.
///
/// ```
/// swift package zerk-graph
/// swift package zerk-graph --format mermaid
/// swift package zerk-graph --target AppCore --target Networking --format dot | dot -Tpng -o graph.png
/// ```
///
/// ## Why it re-runs codegen instead of reading the build artifacts
///
/// The build plugin already writes `Zerk.graph.json` per target, and this could
/// have hunted for those. It does not, for three reasons: they only exist after
/// a successful build, they are deliberately undeclared outputs so nothing
/// guarantees where they are, and finding them means guessing at build-directory
/// layout. Running `ZerkCodegen` here instead makes the command work on a clean
/// checkout and depend on nothing but the sources.
///
/// The cost is small — a codegen pass is parsing plus resolution, no compilation.
///
/// ## Output
///
/// stdout by default, so it pipes and needs no permission. `--output` writes a
/// file; writing inside the package requires
/// `--allow-writing-to-package-directory`, which SwiftPM prompts for.
@main
struct ZerkGraphPlugin: CommandPlugin {

    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let options = try Options(arguments: arguments)

        let targets = context.package.targets
            .compactMap { $0 as? SourceModuleTarget }
            .filter { options.targetNames.isEmpty || options.targetNames.contains($0.name) }
            .sorted { $0.name < $1.name }

        if !options.targetNames.isEmpty {
            let found = Set(targets.map(\.name))
            for missing in options.targetNames.subtracting(found).sorted() {
                throw Failure("no target named '\(missing)' in this package")
            }
        }

        var graphPaths: [String] = []
        for target in targets {
            let sources = target.sourceFiles
                .filter { $0.url.pathExtension == "swift" }
                .map(\.url)
            guard !sources.isEmpty else {
                continue
            }
            let path = try runCodegen(
                tool: context.tool(named: "ZerkCodegen"),
                workDirectory: context.pluginWorkDirectoryURL,
                moduleName: target.name,
                sources: sources,
                settingsFile: Self.settingsFile(
                    searchingIn: [target.directoryURL, context.package.directoryURL]
                )
            )
            graphPaths.append(path)
        }

        guard !graphPaths.isEmpty else {
            throw Failure("no Swift sources found in the selected target(s)")
        }

        try render(
            tool: context.tool(named: "ZerkGraphTool"),
            graphPaths: graphPaths,
            options: options
        )
    }

    // MARK: - Steps

    /// Runs codegen for one module, returning the graph it wrote.
    ///
    /// The generated Swift goes to the plugin's work directory and is never
    /// looked at — it is a by-product here, not the point. Only `--graph` is
    /// wanted, and the tool cannot produce one without the other.
    private func runCodegen(tool: PluginContext.Tool,
                            workDirectory: URL,
                            moduleName: String,
                            sources: [URL],
                            settingsFile: URL?) throws -> String {
        let directory = workDirectory.appending(path: moduleName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let graphFile = directory.appending(path: "Zerk.graph.json")
        var arguments = [directory.appending(path: "Zerk.generated.swift").path]
        if let settingsFile {
            arguments += ["--settings", settingsFile.path]
        }
        arguments += ["--graph", graphFile.path, "--module", moduleName]
        arguments += sources.map(\.path)

        try run(tool.url, arguments: arguments,
                failure: "codegen failed for target '\(moduleName)'")
        return graphFile.path
    }

    private func render(tool: PluginContext.Tool,
                        graphPaths: [String],
                        options: Options) throws {
        var arguments = ["--format", options.format]
        if let output = options.outputPath {
            arguments += ["--output", output]
        }
        arguments += graphPaths

        try run(tool.url, arguments: arguments, failure: "could not render the graph")
    }

    /// Runs a tool with its output left attached to the plugin's own, so
    /// codegen diagnostics reach the developer and the rendered graph reaches
    /// stdout unmediated.
    private func run(_ executable: URL, arguments: [String], failure: String) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw Failure(failure)
        }
    }

    // MARK: - Options

    struct Options {
        var targetNames: Set<String> = []
        var format = "json"
        var outputPath: String?

        init(arguments: [String]) throws {
            var index = 0
            while index < arguments.count {
                let argument = arguments[index]
                guard ["--target", "--format", "--output"].contains(argument) else {
                    throw Failure("""
                        unexpected argument '\(argument)'.
                        Usage: swift package zerk-graph [--target <name>]... [--format json|dot|mermaid] [--output <path>]
                        """)
                }
                guard index + 1 < arguments.count else {
                    throw Failure("\(argument) expects a value")
                }
                let value = arguments[index + 1]
                switch argument {
                case "--target": targetNames.insert(value)
                case "--format": format = value
                default: outputPath = value
                }
                index += 2
            }
        }
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    /// Mirrors the build plugin's lookup — target directory first, then the
    /// package root — so the graph is resolved under the same settings the build
    /// would use. Duplicated rather than shared because a plugin target cannot
    /// import a library target.
    static func settingsFile(searchingIn directories: [URL]) -> URL? {
        for directory in directories {
            let candidate = directory.appending(path: "ZerkSettings.json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}

#if canImport(XcodeProjectPlugin)
extension ZerkGraphPlugin: XcodeCommandPlugin {

    /// Xcode entry point, reached from *Product ▸ … ▸ zerk-graph*. It differs
    /// only in how targets and sources are enumerated; an Xcode target has no
    /// directory of its own, so settings are looked for beside the sources and
    /// then at the project root — the same precedence the SwiftPM path gives.
    func performCommand(context: XcodePluginContext, arguments: [String]) throws {
        let options = try Options(arguments: arguments)

        let targets = context.xcodeProject.targets
            .filter { options.targetNames.isEmpty || options.targetNames.contains($0.displayName) }
            .sorted { $0.displayName < $1.displayName }

        var graphPaths: [String] = []
        for target in targets {
            let sources = target.inputFiles
                .filter { $0.url.pathExtension == "swift" }
                .map(\.url)
            guard !sources.isEmpty else {
                continue
            }

            var searchDirectories: [URL] = []
            var seen = Set<String>()
            for file in sources {
                let directory = file.deletingLastPathComponent()
                if seen.insert(directory.path).inserted {
                    searchDirectories.append(directory)
                }
            }
            searchDirectories.append(context.xcodeProject.directoryURL)

            graphPaths.append(
                try runCodegen(
                    tool: context.tool(named: "ZerkCodegen"),
                    workDirectory: context.pluginWorkDirectoryURL,
                    moduleName: target.displayName,
                    sources: sources,
                    settingsFile: ZerkGraphPlugin.settingsFile(searchingIn: searchDirectories)
                )
            )
        }

        guard !graphPaths.isEmpty else {
            throw Failure("no Swift sources found in the selected target(s)")
        }

        try render(
            tool: context.tool(named: "ZerkGraphTool"),
            graphPaths: graphPaths,
            options: options
        )
    }
}
#endif
