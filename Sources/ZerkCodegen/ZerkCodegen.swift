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
/// Usage: `ZerkCodegen <output.swift> [--settings <path>] <input.swift>...`
///
/// The output path is positional and comes first; everything not consumed by a
/// flag is an input file. Diagnostics go to stderr in the compiler's
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
            var inputPaths: [String] = []

            var index = 1
            while index < arguments.count {
                if arguments[index] == "--settings" {
                    guard index + 1 < arguments.count else {
                        emitUsage()
                        exit(1)
                    }
                    settingsPath = arguments[index + 1]
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
                settingsPath: settingsPath)

            try codeGenerator.run()
        } catch {
            exit(1)
        }
    }

    private static func emitUsage() {
        let message = "Usage: ZerkCodegen <output.swift> [--settings <ZerkSettings.json>] <input.swift> [input.swift...]\n"
        if let data = message.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }
}
