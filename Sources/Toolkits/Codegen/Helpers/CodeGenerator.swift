//
//  CodeGenerator.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

import Foundation
import SwiftParser

/// Runs the whole pipeline for one module: parse every input file, resolve the
/// dependency graph, and write the generated injection code.
///
/// The stages are `SourceCollector` (syntax → records), `ProviderResolver`
/// (which provider serves which key), and `GeneratorOutputBuilder` (records →
/// Swift source). Diagnostics accumulate across stages and are emitted
/// together, so one build surfaces every problem rather than the first.
public struct CodeGenerator {

    /// Thrown to exit non-zero.
    ///
    /// `message` is `nil` when diagnostics have already been emitted and *are*
    /// the error report. It is filled in for the failures that have no source
    /// position to hang a diagnostic on — a file that vanished mid-build, a
    /// non-UTF8 input, a work directory that cannot be written — because
    /// otherwise nothing at all is written and the build fails silently.
    public struct Failure: Error {
        public var message: String? = nil
    }

    let inputPaths: [String]
    let outputPath: String
    var settingsPath: String? = nil
    /// Where to write the ``ZerkGraph`` artifact, or `nil` to write none.
    ///
    /// Opt-in rather than derived from `outputPath`, so invoking the tool by
    /// hand keeps its old contract of writing exactly one file. The build plugin
    /// always asks for it, since it can declare the extra output and let the
    /// build system track it.
    var graphPath: String? = nil
    /// The module name recorded in the graph. Only meaningful alongside
    /// ``graphPath``.
    var moduleName: String? = nil

    public init(inputPaths: [String],
                outputPath: String,
                settingsPath: String? = nil,
                graphPath: String? = nil,
                moduleName: String? = nil) {
        self.inputPaths = inputPaths
        self.outputPath = outputPath
        self.settingsPath = settingsPath
        self.graphPath = graphPath
        self.moduleName = moduleName
    }

    public func run() throws {
        let settings: ZerkSettings
        do {
            settings = try loadSettings()
        } catch let failure as ZerkSettings.LoadFailure {
            emitDiagnostics([
                CodegenDiagnostic(
                    severity: .error,
                    message: failure.message,
                    location: AttributeLocation(filePath: failure.path, line: 1, column: 1)
                )
            ])
            throw Failure()
        }

        let collector = SourceCollector(settings: settings)

        for path in inputPaths {
            let source: String
            do {
                source = try String(contentsOfFile: path, encoding: .utf8)
            } catch {
                // Named, because the build system hands this every source file
                // in the target and "the file couldn't be opened" would not say
                // which one — nor that it is a *Zerk* step reporting it.
                throw Failure(message: "could not read \(path): \(error.localizedDescription)")
            }
            let tree = Parser.parse(source: source)
            collector.walk(tree, path: path)
        }

        // Alias groups merge keys before anything compares them, so resolution
        // and generation are alias-aware without knowing aliases exist.
        // Narrowed to the files that actually put a foreign name into the
        // generated file; see `SourceCollector.resolvedImports(declaredLocally:)`.
        let declaredLocally = Set(collector.declaredAccessRanks.keys)
        let resolvedImports = collector.resolvedImports(declaredLocally: declaredLocally)
        // A qualifier names a module only until this module declares a type of
        // that name. Swift then resolves the bare word to the type — module
        // wide, from any file, whether or not that file declares it — so
        // `Core.Serving` names a *member* and stripping it would rename a local
        // type to something else entirely. The import itself still has to be
        // emitted, so this narrows only what may be stripped, not what is
        // imported.
        let strippableModules = resolvedImports.modules
            .subtracting(declaredLocally.lazy.filter { !$0.contains(".") })
        // Computed from the keys as written, before anything is canonicalized:
        // two modules producing one bare name must not be merged into a single
        // key, and the written spelling is the only place that is visible.
        let clashingBareNames = KeyAliases.clashingBareNames(
            among: collector.writtenKeySpellings,
            modules: strippableModules,
            declaredLocally: declaredLocally)
        let aliases = KeyAliases(declarations: collector.aliasDeclarations,
                                  knownModules: strippableModules,
                                  clashingBareNames: clashingBareNames)
        let rewriter = AliasRewriter(aliases: aliases)
        let keyDisplayNames = rewriter.rewrite(keyDisplayNames: collector.keyDisplayNames)
        let keyNominalNames = rewriter.rewrite(keyNominalNames: collector.keyNominalNames)
        let gate = GenericGate.admitted(rewriter.rewrite(types: collector.types))
        let types = gate.types
        let localValues = rewriter.rewrite(values: collector.values)
        let injectedUses = rewriter.rewrite(injectedUses: collector.injectedUses)
        let markedMembers = rewriter.rewrite(markedMembers: collector.markedMembers)

        let resolution = ProviderResolver(types: types, aliases: aliases, keyDisplayNames: keyDisplayNames).resolve()

        // Imports join the primaries only: they satisfy parameters, and emit no
        // members, because what they resolve is built in another module.
        let imports = ImportedInjectableMerger(
            records: collector.importedInjectables.map {
                var record = $0
                record.typeKey = aliases.representative(for: $0.typeKey)
                return record
            }
        ).merged(
            into: resolution.primaryResolutions,
            localKeys: Set(resolution.resolutions.map(\.injectableKey))
        )

        // Imported values join the matching pool on the same terms, but keyed by
        // name as well, so several of one type stay distinct.
        let importedValues = ImportedValueMerger(
            records: rewriter.rewrite(importedValues: collector.importedValues)
        ).merged(into: localValues)
        let values = importedValues.values

        // After the walk, never during it: a nested type declared below its own
        // use is still the one Swift's lookup picks, so this can only be
        // answered once every declaration in the module is known.
        let nestedNames = NestedNameCheck(declaredAccessRanks: collector.declaredAccessRanks)
            .diagnostics(types: collector.types,
                         markedMembers: collector.markedMembers,
                         injectedUses: collector.injectedUses)

        var diagnostics = collector.diagnostics + gate.diagnostics + resolution.diagnostics
            + imports.diagnostics + importedValues.diagnostics + nestedNames

        if diagnostics.contains(where: { $0.severity == .error }) {
            emitDiagnostics(diagnostics)
            throw Failure()
        }

        let output = GeneratorOutputBuilder(
            values: values,
            resolutions: resolution.resolutions,
            primaryResolutions: KeyIndex(imports.primaries),
            declaredAccessRanks: collector.declaredAccessRanks,
            declaredGenericParameters: collector.declaredGenericParameters,
            keyNominalNames: keyNominalNames,
            injectedUses: injectedUses,
            markedMembers: markedMembers,
            keyDisplayNames: keyDisplayNames,
            importedModules: resolvedImports.modules,
            moduleImportConditions: resolvedImports.conditions,
            primaryVariants: resolution.primaryVariants
        ).build()

        diagnostics += output.diagnostics

        // A same-domain isolated default argument relies on SE-0411 evaluating
        // the expression in the callee's domain. Swift 6 language mode has that
        // always; Swift 5 mode needs complete strict concurrency or the
        // IsolatedDefaultValues upcoming feature. Every other isolated
        // construct Zerk emits — isolated singleton storage, cross-domain
        // async resolution, an isolated member with a nonisolated default —
        // compiles under stock Swift 5, so none of them are gated here.
        if output.usesIsolatedDefaultArguments, !settings.supportsIsolatedDefaultValues {
            let path = settings.sourcePath ?? outputPath
            diagnostics.append(CodegenDiagnostic(
                severity: .error,
                message: "Resolving an isolated dependency into a default argument requires SE-0411, which \(ZerkSettings.fileName) says this target does not have (swiftVersion \"\(settings.swiftVersion)\", strictConcurrency \"\(settings.strictConcurrency.rawValue)\", isolatedDefaultValues \(settings.isolatedDefaultValues)). Set SWIFT_UPCOMING_FEATURE_ISOLATED_DEFAULT_VALUES=YES on the target and \"isolatedDefaultValues\": true here, or set SWIFT_STRICT_CONCURRENCY=complete and \"strictConcurrency\": \"complete\" — or mark the providers 'nonisolated'.",
                location: AttributeLocation(filePath: path, line: 1, column: 1)
            ))
        }

        // Emitted unconditionally, not only on failure: a warning that is
        // dropped whenever the build succeeds is a warning nobody ever sees,
        // which is every case it was written for.
        emitDiagnostics(diagnostics)

        if diagnostics.contains(where: { $0.severity == .error }) {
            throw Failure()
        }

        let url = URL(fileURLWithPath: outputPath)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try output.output.write(to: url, atomically: true, encoding: String.Encoding.utf8)
        } catch {
            throw Failure(message: "could not write \(outputPath): \(error.localizedDescription)")
        }

        // After the Swift, and only once it is written: the graph describes what
        // was emitted, so a run that produced no code should leave no graph
        // claiming otherwise.
        if let graphPath {
            var graph = GraphBuilder(
                values: values,
                resolutions: resolution.resolutions,
                primaryResolutions: KeyIndex(imports.primaries),
                keyDisplayNames: keyDisplayNames
            ).build()
            graph.module = moduleName

            let graphURL = URL(fileURLWithPath: graphPath)
            do {
                try FileManager.default.createDirectory(
                    at: graphURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try graph.encoded().write(to: graphURL, options: .atomic)
            } catch {
                throw Failure(message: "could not write \(graphPath): \(error.localizedDescription)")
            }
        }
    }
    
    /// The plugin resolves the settings file and passes its path explicitly.
    /// When it finds none, the codegen falls back to the directories of the
    /// input files so the tool stays usable standalone.
    private func loadSettings() throws -> ZerkSettings {
        if let settingsPath {
            return try ZerkSettings.load(contentsOfFile: settingsPath)
        }

        var searchPaths: [String] = []
        var seen = Set<String>()
        for path in inputPaths {
            let directory = (path as NSString).deletingLastPathComponent
            if seen.insert(directory).inserted {
                searchPaths.append(directory)
            }
        }
        return try ZerkSettings.load(searchPaths: searchPaths)
    }

    /// Writes diagnostics to stderr as `file:line:column: severity: message`,
    /// the form Xcode and SwiftPM parse to attach them to the developer's own
    /// source rather than to the generated file.
    func emitDiagnostics(_ diagnostics: [CodegenDiagnostic]) {
        for diagnostic in diagnostics {
            let severity = diagnostic.severity == .error ? "error" : "warning"
            let line = "\(diagnostic.location.filePath):\(diagnostic.location.line):\(diagnostic.location.column): \(severity): \(diagnostic.message)\n"
            if let data = line.data(using: .utf8) {
                FileHandle.standardError.write(data)
            }
        }
    }
}
