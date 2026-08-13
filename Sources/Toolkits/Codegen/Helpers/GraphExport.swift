//
//  GraphExport.swift
//  Zerk
//

import Foundation

/// Reads per-module graph files, joins them, and renders the result.
///
/// The public face of the merge-and-render half of `swift package zerk graph`,
/// mirroring how `CodeGenerator` fronts the generation half. Keeping this the
/// only exported symbol lets ``ZerkGraph``, ``GraphMerger`` and ``GraphRenderer``
/// stay internal, where they can change without being API.
public struct GraphExport {

    /// Thrown after a message has been written, to exit non-zero.
    public struct Failure: Error {
        public let message: String
    }

    let inputPaths: [String]
    let format: String
    var outputPath: String? = nil

    public init(inputPaths: [String], format: String, outputPath: String? = nil) {
        self.inputPaths = inputPaths
        self.format = format
        self.outputPath = outputPath
    }

    /// Every format ``run()`` accepts, for a caller building a usage message.
    public static var formats: [String] {
        GraphRenderer.Format.allCases.map(\.rawValue)
    }

    /// The rendered graph, or `nil` when it was written to a file instead.
    @discardableResult
    public func run() throws -> String? {
        guard let format = GraphRenderer.Format(rawValue: format) else {
            throw Failure(message: "unknown format '\(self.format)'. Expected one of: \(Self.formats.joined(separator: ", "))")
        }

        var graphs: [ZerkGraph] = []
        for path in inputPaths {
            do {
                let graph = try JSONDecoder().decode(
                    ZerkGraph.self,
                    from: Data(contentsOf: URL(fileURLWithPath: path))
                )
                // The version is the contract, and a contract nobody checks is
                // decoration. A graph from a newer toolchain decodes "fine" —
                // `Codable` ignores unknown fields and defaults missing ones —
                // so without this the caller silently reads a graph whose
                // meaning has changed, which is the situation the version
                // exists to make detectable.
                guard graph.formatVersion <= ZerkGraph.currentFormatVersion else {
                    throw Failure(message: "the graph at \(path) is format version \(graph.formatVersion), and this tool reads up to \(ZerkGraph.currentFormatVersion). Update Zerk, or regenerate the graph with the version you are running.")
                }
                graphs.append(graph)
            } catch {
                // Named, because a command plugin hands this several files and
                // "the data couldn't be read" would not say which.
                throw Failure(message: "could not read graph at \(path): \(error)")
            }
        }

        let rendered = try GraphRenderer(graph: GraphMerger(graphs: graphs).merge())
            .render(format)

        guard let outputPath else {
            return rendered
        }

        let url = URL(fileURLWithPath: outputPath)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try rendered.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            // A plugin runs sandboxed, so a refused write inside the package is
            // much the likeliest way to reach here — and the fix is a flag
            // nobody guesses. Offered as a probable cause rather than asserted,
            // since a full disk lands on the same line.
            throw Failure(message: "could not write \(outputPath): \(error.localizedDescription)\n"
                + "If that path is inside the package, the plugin needs permission: "
                + "swift package --allow-writing-to-package-directory zerk graph …")
        }
        return nil
    }
}
