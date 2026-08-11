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
                        emitUsage()
                        exit(1)
                    }
                    switch flag {
                    case "--settings": settingsPath = arguments[index + 1]
                    case "--graph": graphPath = arguments[index + 1]
                    default: moduleName = arguments[index + 1]
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
        } catch {
            exit(1)
        }
    }

    private static func emitUsage() {
        let message = "Usage: ZerkCodegen <output.swift> [--settings <ZerkSettings.json>] [--graph <Zerk.graph.json>] [--module <name>] <input.swift> [input.swift...]\n"
        if let data = message.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }
}
