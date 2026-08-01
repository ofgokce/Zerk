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
/// `ZerkInjections.swift`, so resolution sees the whole module at once — the
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

    /// Builds the single codegen command shared by the SwiftPM and Xcode
    /// entry points.
    ///
    /// The generated file is declared as the command's only output, so the
    /// build system reruns codegen exactly when a source file or the settings
    /// file changes. A target with no Swift sources gets no command at all,
    /// rather than a command that would write an empty file.
    private func buildCommands(tool: PluginContext.Tool,
                               workDirectory: URL,
                               inputFiles: [URL],
                               settingsFile: URL?) throws -> [Command] {
        guard !inputFiles.isEmpty else {
            return []
        }

        let outputFile = workDirectory
            .appending(path: "ZerkGenerated")
            .appending(path: "ZerkInjections.swift")

        var arguments = [outputFile.path]
        if let settingsFile {
            arguments += ["--settings", settingsFile.path]
        }
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

        // Xcode targets expose no directory of their own, so the settings file
        // is looked up next to the project and alongside the input files.
        var searchDirectories: [URL] = [
            context.xcodeProject.directoryURL
        ]
        var seen = Set<String>()
        for file in inputFiles {
            let directory = file.deletingLastPathComponent()
            if seen.insert(directory.path).inserted {
                searchDirectories.append(directory)
            }
        }

        return try buildCommands(
            tool: context.tool(named: "ZerkCodegen"),
            workDirectory: context.pluginWorkDirectoryURL,
            inputFiles: inputFiles,
            settingsFile: ZerkPlugin.settingsFile(searchingIn: searchDirectories)
        )
    }
}
#endif
