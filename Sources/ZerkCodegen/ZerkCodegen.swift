//
//  ZerkCodegen.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 8.02.2026.
//

import Foundation
import CodegenToolkit

/// Command-line front end to `CodeGenerator`, invoked by `ZerkPlugin`.
///
/// Usage: `ZerkCodegen <output.swift> [--settings <path>] [--graph <path>] <input.swift>...`
///
/// The output path is positional and comes first; everything not consumed by a
/// flag is an input file. `--graph` additionally writes the resolved dependency
/// graph as JSON, and is omitted when nothing asked for one; `--module` names
/// the module inside it, which matters once several graphs are merged. Diagnostics go to stderr in the compiler's
/// `file:line:column: severity: message` form so the build system renders them
/// against the developer's own source. Exits non-zero on any error diagnostic,
/// which fails the build.
@main
struct ZerkCodegen {
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard arguments.count >= 2 else {
                emitUsage()
                exit(1)
            }

            let outputPath = arguments[0]
            var settingsPath: String?
            var graphPath: String?
            var moduleName: String?
            var inputPaths: [String] = []

            var index = 1
            while index < arguments.count {
                // Both flags take a value, so a missing one would otherwise
                // consume the next input path silently.
                if let flag = ["--settings", "--graph", "--module"].first(where: { $0 == arguments[index] }) {
                    guard index + 1 < arguments.count else {
                        emit("error: \(flag) expects a value.")
                        emitUsage()
                        exit(1)
                    }
                    let value = arguments[index + 1]
                    // A flag where a value belongs is a *missing* value, not a
                    // value that happens to start with dashes. Taking it swallows
                    // the real flag, leaves that flag's own value to become an
                    // input path, and pushes the eventual complaint onto whatever
                    // innocent argument came next — so the message would name the
                    // wrong one.
                    guard !value.hasPrefix("--") else {
                        emit("error: \(flag) expects a value, but the next argument is '\(value)'.")
                        emitUsage()
                        exit(1)
                    }
                    switch flag {
                    case "--settings": settingsPath = value
                    case "--graph": graphPath = value
                    default: moduleName = value
                    }
                    index += 2
                    continue
                }
                inputPaths.append(arguments[index])
                index += 1
            }

            guard !inputPaths.isEmpty else {
                emitUsage()
                exit(1)
            }

            let codeGenerator = CodeGenerator(
                inputPaths: inputPaths,
                outputPath: outputPath,
                settingsPath: settingsPath,
                graphPath: graphPath,
                moduleName: moduleName)

            try codeGenerator.run()
        } catch let failure as CodeGenerator.Failure {
            // A message means nothing else has spoken: the diagnostics carry
            // their own explanation and leave it `nil`, while an I/O failure has
            // no source position to hang one on and would otherwise fail the
            // build with an empty stderr and "Command failed with a nonzero
            // exit code" as the only clue.
            if let message = failure.message {
                emit("error: \(message)")
            }
            exit(1)
        } catch {
            emit("error: \(error.localizedDescription)")
            exit(1)
        }
    }

    private static func emitUsage() {
        emit("Usage: ZerkCodegen <output.swift> [--settings <ZerkSettings.json>] [--graph <Zerk.graph.json>] [--module <name>] <input.swift> [input.swift...]")
    }

    private static func emit(_ message: String) {
        if let data = (message + "\n").data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }
}
