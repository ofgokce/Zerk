//
//  GraphRenderer.swift
//  Zerk
//

/// Renders a ``ZerkPackageGraph`` as something you can look at.
///
/// Both formats draw the same picture: one cluster per module, one node per key,
/// solid edges for dependencies inside a module and dashed ones for imports
/// answered by another module. The dashed edges are the reason the whole command
/// exists — they are the only place the cross-module shape is visible.
///
/// Node *identifiers* are positional (`m0k3`) rather than derived from key
/// names, which sidesteps escaping entirely: Zerk keys legally contain `<`, `>`,
/// `&`, spaces and dots, and both formats would choke on some of those. The real
/// name rides in the label, escaped per format.
struct GraphRenderer {

    let graph: ZerkPackageGraph

    enum Format: String, CaseIterable {
        case json
        case dot
        case mermaid
    }

    func render(_ format: Format) throws -> String {
        switch format {
        case .json:
            return String(decoding: try graph.encoded(), as: UTF8.self)
        case .dot:
            return dot()
        case .mermaid:
            return mermaid()
        }
    }

    // MARK: - Node identity

    /// `module name -> key -> node id`, so an edge can be drawn to a key in
    /// another module without re-deriving anything.
    private var identifiers: [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        for (moduleIndex, module) in graph.modules.enumerated() {
            for (keyIndex, key) in module.keys.enumerated() {
                result[module.name, default: [:]][key.key] = "m\(moduleIndex)k\(keyIndex)"
            }
        }
        return result
    }

    /// What a key is called in the picture: its display name, plus the lifetime
    /// when it is not the default. A transient key is unannotated because most
    /// of them are, and labelling every node "transient" would say nothing.
    private func label(for key: ZerkGraph.Key) -> String {
        guard let provider = key.providers.first(where: \.isPrimary) ?? key.providers.first else {
            return "\(key.displayName)\nimported"
        }
        switch provider.lifetime {
        case "singleton":
            return "\(key.displayName)\nsingleton"
        case "scoped":
            return "\(key.displayName)\nscoped(.\(provider.scope ?? ""))"
        default:
            return key.displayName
        }
    }

    /// Every dependency edge inside one module, as (from key, to key) pairs.
    ///
    /// Deduplicated: two providers of one key depending on the same thing is one
    /// edge in a picture, however many it is in the graph.
    private func edges(in module: ZerkPackageGraph.Module) -> [(from: String, to: String)] {
        var seen = Set<String>()
        var result: [(from: String, to: String)] = []
        for key in module.keys {
            for provider in key.providers {
                for dependency in provider.dependencies
                where dependency.source == "injectable" {
                    guard let target = dependency.key,
                          seen.insert("\(key.key)->\(target)").inserted else {
                        continue
                    }
                    result.append((from: key.key, to: target))
                }
            }
        }
        return result
    }

    // MARK: - Graphviz

    private func dot() -> String {
        let ids = identifiers
        var lines = [
            "digraph Zerk {",
            "    rankdir=LR;",
            "    node [shape=box, style=rounded, fontname=\"Helvetica\"];",
            "    edge [fontname=\"Helvetica\"];"
        ]

        for (index, module) in graph.modules.enumerated() {
            lines.append("    subgraph cluster_\(index) {")
            lines.append("        label=\"\(dotEscaped(module.name))\";")
            lines.append("        style=rounded;")
            for key in module.keys {
                guard let id = ids[module.name]?[key.key] else { continue }
                let shape = key.isImported ? ", style=\"rounded,dashed\"" : ""
                lines.append("        \(id) [label=\"\(dotEscaped(label(for: key)))\"\(shape)];")
            }
            lines.append("    }")
        }

        for module in graph.modules {
            for edge in edges(in: module) {
                guard let from = ids[module.name]?[edge.from],
                      let to = ids[module.name]?[edge.to] else { continue }
                lines.append("    \(from) -> \(to);")
            }
        }

        for resolved in graph.imports {
            guard let from = ids[resolved.consumer]?[resolved.key] else { continue }
            for provider in resolved.providers {
                guard let to = ids[provider]?[resolved.key] else { continue }
                lines.append("    \(from) -> \(to) [style=dashed, constraint=false];")
            }
        }

        lines.append("}")
        return lines.joined(separator: "\n")
    }

    /// Backslashes first: escaping the quotes first would then double the
    /// backslashes this adds.
    private func dotEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    // MARK: - Mermaid

    private func mermaid() -> String {
        let ids = identifiers
        var lines = ["graph LR"]

        for module in graph.modules {
            lines.append("    subgraph \(mermaidEscaped(module.name))")
            for key in module.keys {
                guard let id = ids[module.name]?[key.key] else { continue }
                lines.append("        \(id)[\"\(mermaidEscaped(label(for: key)))\"]")
            }
            lines.append("    end")
        }

        for module in graph.modules {
            for edge in edges(in: module) {
                guard let from = ids[module.name]?[edge.from],
                      let to = ids[module.name]?[edge.to] else { continue }
                lines.append("    \(from) --> \(to)")
            }
        }

        for resolved in graph.imports {
            guard let from = ids[resolved.consumer]?[resolved.key] else { continue }
            for provider in resolved.providers {
                guard let to = ids[provider]?[resolved.key] else { continue }
                lines.append("    \(from) -.-> \(to)")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Mermaid has no escape character, so the hostile characters go out as HTML
    /// entities — which it does understand inside a quoted label. `<` matters
    /// most: Zerk keys are full of `Cache<String>`, and an unescaped `<` ends the
    /// label early and corrupts the rest of the diagram.
    private func mermaidEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "#amp;")
            .replacingOccurrences(of: "\"", with: "#quot;")
            .replacingOccurrences(of: "<", with: "#lt;")
            .replacingOccurrences(of: ">", with: "#gt;")
            .replacingOccurrences(of: "\n", with: "<br/>")
    }
}
