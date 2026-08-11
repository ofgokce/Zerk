//
//  ZerkPackageGraph.swift
//  Zerk
//

import Foundation

/// Several modules' graphs together, with the edges between them drawn in.
///
/// What `swift package zerk-graph` produces, and the one view Zerk does not have
/// at build time. Resolution is module-scoped by design: a module knows a key is
/// `@ImportedInjectable` and knows nothing else about it, which is exactly the
/// isolation that makes the plugin cheap and correct. Only something looking at
/// every module at once can say *which* module answers that import.
///
/// ## This is presentation, not resolution
///
/// The stitching here changes nothing. It runs after every module has already
/// been resolved and generated independently, it feeds back into no build, and
/// it produces no diagnostics. It joins two facts Zerk already records — "module
/// A imports key K" and "module B exports key K" — for the benefit of a reader.
///
/// Cross-module *inference* remains deliberately unbuilt. Nothing here brings it
/// closer or depends on it.
struct ZerkPackageGraph: Codable, Equatable {

    static let currentFormatVersion = 1

    var formatVersion: Int = ZerkPackageGraph.currentFormatVersion
    /// Every module that contributed a graph, sorted by name.
    let modules: [Module]
    /// Imports matched to the module that exports them.
    let imports: [ResolvedImport]
    /// Imports nothing in this package exports. See ``UnresolvedImport``.
    let unresolvedImports: [UnresolvedImport]

    struct Module: Codable, Equatable {
        let name: String
        let keys: [ZerkGraph.Key]
        let values: [ZerkGraph.Value]
    }

    /// One module's import, answered by another module in the same package.
    struct ResolvedImport: Codable, Equatable {
        let key: String
        /// The module that wrote `@ImportedInjectable`.
        let consumer: String
        /// The modules exporting the key, sorted.
        ///
        /// A list because two modules in one package may both export a key, and
        /// which one the consumer actually imported is a Swift-level fact —
        /// decided by its `import` statements — that Zerk never sees. One entry
        /// is the ordinary case; more than one is worth a reader's attention
        /// rather than a silent pick.
        let providers: [String]
    }

    /// An import with no exporter in this package.
    ///
    /// Not an error, and reported rather than dropped. The usual cause is
    /// perfectly ordinary — the key lives in a *different* package, which this
    /// command cannot see. The other cause is a genuine mistake, and it is only
    /// visible if unmatched imports are shown instead of quietly discarded.
    struct UnresolvedImport: Codable, Equatable {
        let key: String
        let consumer: String
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
