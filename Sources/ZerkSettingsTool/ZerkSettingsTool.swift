//
//  ZerkSettingsTool.swift
//  Zerk
//

import Foundation
import CodegenToolkit

/// Command-line front end to `XcodeSettingsImport`, invoked by `ZerkCLI`.
///
/// Usage:
/// `ZerkSettingsTool --project <path> [--target <name>] [--output <path>]`
///
/// The second half of `swift package zerk settings`, split for the reason
/// `ZerkGraphTool` is: a plugin may depend on executables but cannot import a
/// library target, so everything worth testing lives here rather than in the
/// plugin, where no test can reach it.
///
/// Running `xcodebuild` is this tool's job rather than the plugin's for the same
/// reason. It works from inside the plugin sandbox — measured, not assumed —
/// and putting it here means the whole path from a project to a settings file
/// can be exercised without a plugin host.
///
/// Writes to stdout unless `--output` says otherwise, so the common case is to
/// read the result before adopting it, and needs no package-directory
/// permission.
@main
struct ZerkSettingsTool {
    static func main() {
        var projectPath: String?
        var targetName: String?
        var outputPath: String?

        let arguments = Array(CommandLine.arguments.dropFirst())
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            guard ["--project", "--target", "--output"].contains(argument) else {
                fail("unexpected argument '\(argument)'.\n\(usage)")
            }
            guard index + 1 < arguments.count else {
                fail("\(argument) expects a value.\n\(usage)")
            }
            let value = arguments[index + 1]
            // A flag where a value belongs is a *missing* value, not a value
            // that happens to start with dashes — the same reading `ZerkCodegen`
            // gives, so a mistake is reported against the argument that made it.
            guard !value.hasPrefix("--") else {
                fail("\(argument) expects a value, but the next argument is '\(value)'.\n\(usage)")
            }
            switch argument {
            case "--project": projectPath = value
            case "--target": targetName = value
            default: outputPath = value
            }
            index += 2
        }

        guard let projectPath else {
            fail("--project is required.\n\(usage)")
        }

        let dump: Data
        do {
            dump = try showBuildSettings(project: projectPath)
        } catch let failure as Failure {
            fail(failure.message)
        } catch {
            fail("could not run xcodebuild: \(error.localizedDescription)")
        }

        let contents: String
        let resolvedTarget: String
        do {
            (contents, resolvedTarget) = try XcodeSettingsImport.settingsFile(
                fromShowBuildSettings: dump, target: targetName)
        } catch let failure as XcodeSettingsImport.Failure {
            fail(failure.message)
        } catch {
            fail("could not read the build settings: \(error.localizedDescription)")
        }

        guard let outputPath else {
            FileHandle.standardOutput.write(Data(contents.utf8))
            return
        }

        do {
            let url = URL(fileURLWithPath: outputPath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            // Named, because the likeliest cause is the plugin sandbox rather
            // than anything wrong with the path, and "permission denied" alone
            // sends the reader to `chmod`.
            fail("""
                could not write \(outputPath): \(error.localizedDescription)
                Writing inside the package needs 'swift package --allow-writing-to-package-directory zerk settings …'.
                """)
        }

        FileHandle.standardError.write(
            Data("Wrote \(outputPath) from target '\(resolvedTarget)'.\n".utf8))
    }

    private struct Failure: Error {
        let message: String
    }

    /// Asks Xcode for every target's resolved build settings.
    ///
    /// `-showBuildSettings` reports one entry per target, and a setting the
    /// target does not set is simply absent — which is what lets the mapping
    /// leave a key out rather than invent a default for it.
    ///
    /// `--target` is applied afterwards rather than passed on as `-target`.
    /// Handing an unknown name to xcodebuild gets `status 65` and a paragraph
    /// about a result bundle; selecting here answers with the names the project
    /// actually has, which is the question the reader is about to ask.
    private static func showBuildSettings(project: String) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = ["-showBuildSettings", "-project", project, "-json"]

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            throw Failure(message: """
                could not run xcodebuild: \(error.localizedDescription)
                Reading a target's build settings needs Xcode; on Linux, write \
                \(XcodeSettingsImport.settingsFileName) by hand.
                """)
        }

        // Read before waiting: xcodebuild's output is far larger than a pipe
        // buffer, and waiting first would deadlock once it fills.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(
            data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw Failure(message: """
                xcodebuild failed (status \(process.terminationStatus)).
                \(errorText.trimmingCharacters(in: .whitespacesAndNewlines))
                """)
        }
        return data
    }

    static let usage = """
        Usage: ZerkSettingsTool --project <path> [--target <name>] [--output <path>]
        """

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
        exit(1)
    }
}
