//
//  ZerkGraphTool.swift
//  Zerk
//

import Foundation
import CodegenToolkit

/// Command-line front end to `GraphExport`, invoked by `ZerkGraphPlugin`.
///
/// Usage: `ZerkGraphTool [--format <json|dot|mermaid>] [--output <path>] <graph.json>...`
///
/// The second half of `swift package zerk-graph`. The command plugin runs
/// `ZerkCodegen` once per target to produce the inputs, then this to join them —
/// a split the plugin API forces, since a plugin may depend on executables but
/// cannot import library targets. It earns its keep anyway: everything it does
/// is testable without a plugin host.
///
/// Writes to stdout unless `--output` says otherwise, so the common case pipes
/// into `jq` or `dot` and needs no package-directory permission.
@main
struct ZerkGraphTool {
    static func main() {
        var format = "json"
        var outputPath: String?
        var inputPaths: [String] = []

        let arguments = Array(CommandLine.arguments.dropFirst())
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--format", "--output":
                guard index + 1 < arguments.count else {
                    fail("\(arguments[index]) expects a value")
                }
                if arguments[index] == "--format" {
                    format = arguments[index + 1]
                } else {
                    outputPath = arguments[index + 1]
                }
                index += 2
            default:
                inputPaths.append(arguments[index])
                index += 1
            }
        }

        guard !inputPaths.isEmpty else {
            fail("Usage: ZerkGraphTool [--format <\(GraphExport.formats.joined(separator: "|"))>] [--output <path>] <graph.json>...")
        }

        do {
            let rendered = try GraphExport(
                inputPaths: inputPaths,
                format: format,
                outputPath: outputPath
            ).run()

            if let rendered {
                write(rendered + "\n", to: .standardOutput)
            } else if let outputPath {
                // To stderr, so `--output` alongside a redirect still leaves a
                // clean file.
                write("Zerk: wrote \(outputPath)\n", to: .standardError)
            }
        } catch let failure as GraphExport.Failure {
            fail(failure.message)
        } catch {
            fail("\(error)")
        }
    }

    private static func fail(_ message: String) -> Never {
        write("error: \(message)\n", to: .standardError)
        exit(1)
    }

    private static func write(_ text: String, to handle: FileHandle) {
        if let data = text.data(using: .utf8) {
            handle.write(data)
        }
    }
}
