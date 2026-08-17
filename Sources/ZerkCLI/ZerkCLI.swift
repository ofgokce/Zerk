//
//  ZerkCLI.swift
//  Zerk
//

import PackagePlugin
import Foundation
#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin
#endif

/// `swift package zerk …` — Zerk's command-line surface.
///
/// A **command** plugin, not a build tool one: it runs when you ask, never as
/// part of a build, and is not attached to a target. (`ZerkPlugin` is the one
/// you attach.)
///
/// SwiftPM gives a plugin a single verb, so the shape here is `zerk` plus a
/// subcommand — leaving room for the next one without claiming a second
/// top-level verb:
///
/// ```
/// swift package zerk graph --format mermaid
/// swift package zerk help
/// ```
@main
struct ZerkCLI: CommandPlugin {

    func performCommand(context: PluginContext, arguments: [String]) async throws {
        switch try Command(arguments: arguments) {
        case .help(let topic):
            print(Self.help(for: topic))

        case .graph(let options):
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
                graphPaths.append(
                    try runCodegen(
                        tool: context.tool(named: "ZerkCodegen"),
                        workDirectory: context.pluginWorkDirectoryURL,
                        moduleName: target.name,
                        sources: sources,
                        settingsFile: Self.settingsFile(
                            searchingIn: [target.directoryURL, context.package.directoryURL]
                        )
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

    // MARK: - Steps

    /// Runs codegen for one module, returning the graph it wrote.
    ///
    /// Codegen is re-run rather than the build artifacts read, because those
    /// only exist after a successful build, are deliberately undeclared outputs,
    /// and would have to be found by guessing at build-directory layout. This
    /// works on a clean checkout and depends on nothing but the sources.
    ///
    /// The generated Swift goes to the plugin's work directory and is never
    /// looked at — a by-product here, since the tool cannot write a graph
    /// without also writing it.
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
                        options: GraphOptions) throws {
        var arguments = ["--format", options.format]
        if let output = options.outputPath {
            arguments += ["--output", output]
        }
        arguments += graphPaths

        try run(tool.url, arguments: arguments, failure: "could not render the graph")
    }

    /// Runs a tool with its output left attached to the plugin's own, so codegen
    /// diagnostics reach the developer and a rendered graph reaches stdout
    /// unmediated.
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

    // MARK: - Commands

    enum Command {
        case help(topic: String?)
        case graph(GraphOptions)

        init(arguments: [String]) throws {
            // Bare `swift package zerk` prints help rather than erroring: there
            // is no sensible default action, and a usage message is a better
            // answer than a complaint.
            guard let first = arguments.first else {
                self = .help(topic: nil)
                return
            }

            if Self.isHelpFlag(first) || first == "help" {
                // `zerk help graph` and `zerk --help graph` both reach the
                // graph topic.
                self = .help(topic: arguments.dropFirst().first)
                return
            }

            let rest = Array(arguments.dropFirst())

            switch first {
            case "graph":
                if rest.contains(where: Self.isHelpFlag) {
                    self = .help(topic: "graph")
                    return
                }
                self = .graph(try GraphOptions(arguments: rest))
            default:
                throw Failure("""
                    unknown command '\(first)'.
                    \(ZerkCLI.usage)
                    """)
            }
        }

        private static func isHelpFlag(_ argument: String) -> Bool {
            argument == "--help" || argument == "-h"
        }
    }

    struct GraphOptions {
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
                        \(ZerkCLI.graphUsage)
                        """)
                }
                guard index + 1 < arguments.count else {
                    throw Failure("\(argument) expects a value")
                }
                let value = arguments[index + 1]
                // A flag where a value belongs is a missing value. Without this,
                // `--format --output /tmp/x.json` reads as format `--output` and
                // the complaint lands on `/tmp/x.json`, which is the one
                // argument that was written correctly. Duplicated from the two
                // executables rather than shared, because a plugin target cannot
                // import a library target.
                guard !value.hasPrefix("--") else {
                    throw Failure("\(argument) expects a value, but the next argument is '\(value)'")
                }
                switch argument {
                case "--target": targetNames.insert(value)
                case "--format": format = value
                default: outputPath = value
                }
                index += 2
            }
        }
    }

    // MARK: - Help

    static let usage = """
        Usage: swift package zerk <command> [options]

        Commands:
          graph     Export the resolved dependency graph for this package.
          help      Show this message.

        Run 'swift package zerk <command> --help' for a command's options.
        """

    static let graphUsage = """
        Usage: swift package zerk graph [options]

        Resolves every target's dependency graph and prints it, joining the
        modules together: an @ImportedInjectable key in one module is matched to
        the module that exports it.

        Options:
          --target <name>    Only this target. Repeat for several; default is all.
          --format <format>  text, json (default), dot, or mermaid.
          --output <path>    Write to a file instead of stdout. Writing inside the
                             package needs the plugin to be run as
                             'swift package --allow-writing-to-package-directory
                             zerk graph …'.
          -h, --help         Show this message.

        Examples:
          swift package zerk graph
          swift package zerk graph --format mermaid
          swift package zerk graph --format text
          swift package zerk graph --target AppCore --format dot | dot -Tpng -o graph.png
          swift package zerk graph --format json --output /tmp/graph.json

        The graph is resolved from source, so no prior build is needed. Each
        build also writes a single-module Zerk.graph.json beside its generated
        Swift; this is the whole-package view of the same data.
        """

    static func help(for topic: String?) -> String {
        switch topic {
        case "graph": return graphUsage
        default: return usage
        }
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    /// Mirrors the build plugin's lookup — target directory first, then the
    /// package root — so the graph is resolved under the same settings a build
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
extension ZerkCLI: XcodeCommandPlugin {

    /// Xcode entry point, reached from the project's plugin menu. It differs
    /// only in how targets and sources are enumerated; an Xcode target has no
    /// directory of its own, so settings are looked for beside the sources and
    /// then at the project root — the same precedence the SwiftPM path gives.
    func performCommand(context: XcodePluginContext, arguments: [String]) throws {
        switch try Command(arguments: arguments) {
        case .help(let topic):
            print(Self.help(for: topic))

        case .graph(let options):
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
                        settingsFile: ZerkCLI.settingsFile(searchingIn: searchDirectories)
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
}
#endif
