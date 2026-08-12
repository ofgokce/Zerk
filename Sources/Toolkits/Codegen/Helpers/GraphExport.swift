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
    /// Narrow the result to keys nothing in the package resolves.
    var unusedOnly: Bool = false

    public init(inputPaths: [String],
                format: String,
                outputPath: String? = nil,
                unusedOnly: Bool = false) {
        self.inputPaths = inputPaths
        self.format = format
        self.outputPath = outputPath
        self.unusedOnly = unusedOnly
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
                graphs.append(
                    try JSONDecoder().decode(
                        ZerkGraph.self,
                        from: Data(contentsOf: URL(fileURLWithPath: path))
                    )
                )
            } catch {
                // Named, because a command plugin hands this several files and
                // "the data couldn't be read" would not say which.
                throw Failure(message: "could not read graph at \(path): \(error)")
            }
        }

        let package = GraphMerger(graphs: graphs).merge()
        var rendered: String

        if unusedOnly {
            let analysis = GraphAnalysis(graph: package)
            rendered = try GraphRenderer(graph: analysis.unusedGraph()).render(format)
            // The other formats carry their own emptiness legibly — an empty
            // JSON graph, an empty diagram. A blank page does not, and "nothing
            // to report" is the answer people most want to be sure of.
            if format == .text {
                let count = analysis.unusedKeys().count
                rendered = count == 0
                    ? "No unused keys: every registration is resolved by something."
                    : "\(count) \(count == 1 ? "key is" : "keys are") registered but resolved by nothing:\n\n\(rendered)"
            }
        } else {
            rendered = try GraphRenderer(graph: package).render(format)
        }

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
