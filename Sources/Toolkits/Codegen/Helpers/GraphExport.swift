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
    ///
    /// `CustomStringConvertible` so that interpolating one gives the sentence
    /// rather than `Failure(message: "…")`. Nothing should be interpolating one
    /// — a caller has `message` — but the synthesized description reached a
    /// developer once already, through a `catch` that re-wrapped a failure it
    /// was not written for.
    public struct Failure: Error, CustomStringConvertible {
        public let message: String

        public var description: String { message }
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
            let graph: ZerkGraph
            do {
                graph = try JSONDecoder().decode(
                    ZerkGraph.self,
                    from: Data(contentsOf: URL(fileURLWithPath: path))
                )
            } catch {
                // Named, because a command plugin hands this several files and
                // "the data couldn't be read" would not say which.
                throw Failure(message: "could not read graph at \(path): \(error)")
            }

            // The version is the contract, and a contract nobody checks is
            // decoration. `Codable` ignores unknown fields and defaults missing
            // ones, so a graph of any other version decodes "fine" and the
            // caller silently reads one whose meaning has changed — the
            // situation the version exists to make detectable.
            //
            // Equality, not "no newer than": an older graph is not a subset of a
            // newer one. Version 3 exists because `isAsync`/`isThrowing` were
            // repurposed from what building a provider costs to what *reading*
            // it costs, so a version 2 document carries the old answers under
            // the new names — and the merged output is stamped with the current
            // version, leaving nothing downstream able to tell. The realistic
            // way to meet this is a `Zerk.graph.json` left in a work directory
            // from before an upgrade. There is no migration to offer, so the
            // honest answer is to name the version and ask for a rebuild; a
            // `minimumReadableFormatVersion` beside the current one is where
            // forward compatibility would go if it were ever wanted.
            //
            // Deliberately *outside* the `do`. Inside it, the catch written for
            // decode failures swallowed this one and wrapped it in another
            // `Failure` — printing the path twice, with `Failure(message: …)`
            // around the sentence the developer was meant to read.
            guard graph.formatVersion == ZerkGraph.currentFormatVersion else {
                throw Failure(message: "the graph at \(path) is format version \(graph.formatVersion), and this tool reads version \(ZerkGraph.currentFormatVersion). Rebuild to regenerate it, or run the Zerk version that wrote it.")
            }
            graphs.append(graph)
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
