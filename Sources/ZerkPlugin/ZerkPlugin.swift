//
//  ZerkPlugin.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 8.02.2026.
//

import PackagePlugin
import Foundation
#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin
#endif

/// The build-tool plugin that runs `ZerkCodegen` over a target's sources.
///
/// Attach it to every target that *declares* injectables. It feeds the
/// generator every `.swift` file in the target and gets back one
/// `Zerk.generated.swift`, so resolution sees the whole module at once — the
/// reason code generation lives here rather than in the attached macros.
///
/// Both plugin flavors are implemented: SwiftPM (`BuildToolPlugin`) and Xcode
/// projects (`XcodeBuildToolPlugin`). They differ only in how they enumerate
/// sources and where they look for `ZerkSettings.json`.
@main
struct ZerkPlugin: BuildToolPlugin {
    static let settingsFileName = "ZerkSettings.json"

    /// SwiftPM entry point. Non-source targets are skipped, and
    /// `ZerkSettings.json` is looked for in the target directory then the
    /// package root.
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let target = target as? SourceModuleTarget else {
            return []
        }

        let inputFiles = target.sourceFiles
            .filter { $0.url.pathExtension == "swift" }
            .map(\.url)

        return try buildCommands(
            tool: context.tool(named: "ZerkCodegen"),
            workDirectory: context.pluginWorkDirectoryURL,
            moduleName: target.name,
            inputFiles: inputFiles,
            settingsFile: Self.settingsFile(
                searchingIn: [
                    target.directoryURL,
                    context.package.directoryURL
                ]
            )
        )
    }

    /// `ZerkSettings.json` is looked up in the target directory first, then the
    /// package root; the target wins. It is passed to the tool *and* declared
    /// as an input file, so editing it triggers regeneration.
    static func settingsFile(searchingIn directories: [URL]) -> URL? {
        for directory in directories {
            let candidate = directory.appending(path: settingsFileName)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// Where to look for `ZerkSettings.json` for an *Xcode* target, most
    /// specific first.
    ///
    /// An Xcode target has no directory of its own, so the nearest thing is
    /// where its sources sit — and that can be several directories.
    /// `inputFiles` arrives in whatever order Xcode enumerated it, which would
    /// have made the winner depend on that order; sorting settles it.
    ///
    /// Shallowest first, then by path: a file meant for the whole target sits at
    /// the root of its sources, and anything deeper would be a per-folder
    /// setting, which Zerk has no notion of. The project directory goes last, so
    /// a target's own file beats the project's — the same precedence the SwiftPM
    /// path gets from `[target, package]`.
    static func settingsSearchDirectories(forSources sources: [URL],
                                          projectRoot: URL) -> [URL] {
        var directories: [URL] = []
        var seen = Set<String>()
        for file in sources {
            let directory = file.deletingLastPathComponent()
            if seen.insert(directory.path).inserted {
                directories.append(directory)
            }
        }
        directories.sort {
            $0.pathComponents.count == $1.pathComponents.count
                ? $0.path < $1.path
                : $0.pathComponents.count < $1.pathComponents.count
        }
        return directories + [projectRoot]
    }

    /// Builds the single codegen command shared by the SwiftPM and Xcode
    /// entry points.
    ///
    /// The generated Swift is the command's only *declared* output, so the build
    /// system reruns codegen exactly when a source file or the settings file
    /// changes. A target with no Swift sources gets no command at all, rather
    /// than a command that would write an empty file.
    ///
    /// `Zerk.graph.json` is written beside it but deliberately **not declared**.
    /// SwiftPM routes a declared output it cannot compile into the target's
    /// *resource bundle* — measured, not assumed: declaring it put
    /// `Zerk.graph.json` inside `Zerk_<Target>.bundle`, which would ship the
    /// file in every app using Zerk, absolute developer paths and all, and
    /// conjure a `Bundle.module` for targets that had no resources before.
    ///
    /// Leaving it undeclared costs nothing in staleness: the same invocation
    /// writes both files, and the `.swift` output already forces that invocation
    /// to rerun whenever any input changes.
    private func buildCommands(tool: PluginContext.Tool,
                               workDirectory: URL,
                               moduleName: String,
                               inputFiles: [URL],
                               settingsFile: URL?) throws -> [Command] {
        guard !inputFiles.isEmpty else {
            return []
        }

        let outputFile = workDirectory.appending(path: "Zerk.generated.swift")
        let graphFile = workDirectory.appending(path: "Zerk.graph.json")

        var arguments = [outputFile.path]
        if let settingsFile {
            arguments += ["--settings", settingsFile.path]
        }
        arguments += ["--graph", graphFile.path, "--module", moduleName]
        arguments += inputFiles.map(\.path)

        return [
            .buildCommand(
                displayName: "Zerk: Generate injection codes",
                executable: tool.url,
                arguments: arguments,
                inputFiles: inputFiles + (settingsFile.map { [$0] } ?? []),
                outputFiles: [outputFile]
            )
        ]
    }
}

#if canImport(XcodeProjectPlugin)
extension ZerkPlugin: XcodeBuildToolPlugin {
    /// Xcode entry point, which differs only in how sources and the settings
    /// file are located — an Xcode target has no directory of its own.
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        let inputFiles = target.inputFiles
            .filter { $0.url.pathExtension == "swift" }
            .map(\.url)

        let searchDirectories = ZerkPlugin.settingsSearchDirectories(
            forSources: inputFiles,
            projectRoot: context.xcodeProject.directoryURL)

        return try buildCommands(
            tool: context.tool(named: "ZerkCodegen"),
            workDirectory: context.pluginWorkDirectoryURL,
            moduleName: target.displayName,
            inputFiles: inputFiles,
            settingsFile: ZerkPlugin.settingsFile(searchingIn: searchDirectories)
        )
    }
}
#endif
