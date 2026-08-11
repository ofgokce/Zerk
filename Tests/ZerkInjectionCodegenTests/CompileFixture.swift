//
//  CompileFixture.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 28.07.2026.
//

import Foundation
import SwiftParser
@testable import CodegenToolkit

/// Runs the codegen over a source fixture and type-checks the result with a
/// real compiler.
///
/// Golden-string tests cannot catch isolation errors: generated text can look
/// exactly right and still not compile. Everything about isolation, effects,
/// and `sending` has to be verified by `swiftc`, under both language modes and
/// both `SWIFT_DEFAULT_ACTOR_ISOLATION` values.
///
/// The fixture is type-checked standalone — `import Zerk` and the generated
/// `macro Injected` declarations are stripped and a bare `enum Zerk<Injectable> {}` is
/// substituted — so no build of the Zerk module is required.
enum CompileFixture {

    /// Counts the `extension Zerk<Key> { … }` blocks that carry members,
    /// ignoring the per-key `Interjection` namespaces the plugin also emits.
    /// Tests asserting "one extension per key" mean the member ones.
    static func memberExtensionCount(in generated: String) -> Int {
        generated
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.hasPrefix("extension Zerk<") && !$0.contains(".Interjection") }
            .count
    }

    struct Result {
        let generated: String
        let didCompile: Bool
        let compilerOutput: String
        /// `true` when no usable Swift compiler was found, or when it rejected
        /// the requested flags. Callers should treat this as "not verified"
        /// rather than "passed".
        let skipped: Bool
    }

    /// How a Swift 5 language mode target opts in to SE-0411. Either one is
    /// sufficient on its own, and they are independent of each other.
    enum SE0411Unlock {
        /// Stock Swift 5: no opt-in, so isolated default arguments are rejected.
        case none
        /// `SWIFT_UPCOMING_FEATURE_ISOLATED_DEFAULT_VALUES = YES`.
        case upcomingFeature
        /// `SWIFT_STRICT_CONCURRENCY = complete`.
        case completeConcurrency
    }

    struct Options {
        var swiftVersion: String = "6"
        /// `nil` leaves the setting at the compiler default.
        var defaultActorIsolation: String? = nil
        /// Flags beyond the language mode, e.g. the SE-0411 opt-ins.
        var extraFlags: [String] = []
        /// Settings handed to the codegen. Should agree with the flags above;
        /// disagreement is itself worth testing.
        var settings: ZerkSettings = .default

        static let swift6 = Options()

        /// Swift 6 with the named compilation conditions set, as
        /// `SWIFT_ACTIVE_COMPILATION_CONDITIONS` would.
        ///
        /// The generated file's `#if` guards are the developer's own text, so
        /// the only way to know they landed on the right declarations is to
        /// compile the same source twice with different conditions and check
        /// that both build.
        static func swift6(defining conditions: String...) -> Options {
            var options = Options()
            options.extraFlags = conditions.map { "-D\($0)" }
            return options
        }

        static func swift6(defaultIsolation: String?) -> Options {
            var options = Options()
            options.defaultActorIsolation = defaultIsolation
            options.settings = ZerkSettings(
                defaultActorIsolation: defaultIsolation.map { $0 == "nonisolated" ? .nonisolated : .globalActor($0) } ?? .nonisolated,
                swiftVersion: "6",
                sourcePath: nil
            )
            return options
        }

        /// The compiler flags and the `ZerkSettings.json` values are set
        /// together, because the whole point of the settings file is to restate
        /// build settings the plugin cannot see. A test that set one without the
        /// other would be testing a misconfigured target.
        static func swift5(defaultIsolation: String?, unlock: SE0411Unlock = .none) -> Options {
            var options = Options.swift6(defaultIsolation: defaultIsolation)
            options.swiftVersion = "5"
            options.settings.swiftVersion = "5"

            switch unlock {
            case .none:
                break
            case .upcomingFeature:
                options.extraFlags = ["-enable-upcoming-feature", "IsolatedDefaultValues"]
                options.settings.isolatedDefaultValues = true
            case .completeConcurrency:
                options.extraFlags = ["-strict-concurrency=complete"]
                options.settings.strictConcurrency = .complete
            }

            return options
        }
    }

    // MARK: - Entry point

    static func run(source: String, options: Options = .swift6) throws -> Result {
        let generated = generate(source: source, settings: options.settings)
        return try compile(source: source, generated: generated, options: options)
    }

    /// Codegen only — for assertions that do not need a compiler.
    static func generate(source: String, settings: ZerkSettings = .default) -> String {
        generateOutput(source: source, settings: settings).output
    }

    /// The full generator result, for assertions about what the generated code
    /// *contains* rather than what it says.
    static func generateOutput(source: String, settings: ZerkSettings = .default) -> GeneratorOutput {
        let collector = SourceCollector(settings: settings)
        collector.walk(Parser.parse(source: source))

        let aliases = KeyAliases(declarations: collector.aliasDeclarations,
                                  knownModules: collector.importedModules)
        let rewriter = AliasRewriter(aliases: aliases)
        // Mirrors CodeGenerator: registrations the emitter cannot spell are
        // dropped before anything asks which provider backs their key.
        let gate = GenericGate.admitted(rewriter.rewrite(types: collector.types))
        let resolution = ProviderResolver(
            types: gate.types,
            aliases: aliases,
            keyDisplayNames: rewriter.rewrite(keyDisplayNames: collector.keyDisplayNames)
        ).resolve()
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
        let importedValues = ImportedValueMerger(
            records: rewriter.rewrite(importedValues: collector.importedValues)
        ).merged(into: rewriter.rewrite(values: collector.values))
        return GeneratorOutputBuilder(
            values: importedValues.values,
            resolutions: resolution.resolutions,
            primaryResolutions: KeyIndex(imports.primaries),
            moduleAccessLevels: collector.moduleAccessLevels,
            injectedUses: rewriter.rewrite(injectedUses: collector.injectedUses),
            markedMembers: rewriter.rewrite(markedMembers: collector.markedMembers),
            keyDisplayNames: rewriter.rewrite(keyDisplayNames: collector.keyDisplayNames),
            importedModules: collector.importedModules,
            moduleImportConditions: collector.moduleImportConditions,
            primaryVariants: resolution.primaryVariants
        ).build()
    }

    /// The graph artifact for a fixture, built through the same pipeline the
    /// plugin runs so the two cannot describe different things.
    static func graph(source: String, settings: ZerkSettings = .default) -> ZerkGraph {
        let collector = SourceCollector(settings: settings)
        collector.walk(Parser.parse(source: source))

        let aliases = KeyAliases(declarations: collector.aliasDeclarations,
                                  knownModules: collector.importedModules)
        let rewriter = AliasRewriter(aliases: aliases)
        let gate = GenericGate.admitted(rewriter.rewrite(types: collector.types))
        let resolution = ProviderResolver(
            types: gate.types,
            aliases: aliases,
            keyDisplayNames: rewriter.rewrite(keyDisplayNames: collector.keyDisplayNames)
        ).resolve()
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
        let importedValues = ImportedValueMerger(
            records: rewriter.rewrite(importedValues: collector.importedValues)
        ).merged(into: rewriter.rewrite(values: collector.values))

        return GraphBuilder(
            values: importedValues.values,
            resolutions: resolution.resolutions,
            primaryResolutions: KeyIndex(imports.primaries),
            keyDisplayNames: rewriter.rewrite(keyDisplayNames: collector.keyDisplayNames)
        ).build()
    }

    /// Codegen plus the diagnostics that only `ProviderResolver` can produce.
    ///
    /// `generateOutput` reports what the *builder* found; provider ambiguity is
    /// settled a stage earlier, so tests about it need both halves.
    static func generateWithResolution(source: String,
                                       settings: ZerkSettings = .default)
    -> (output: GeneratorOutput, diagnostics: [CodegenDiagnostic]) {
        let collector = SourceCollector(settings: settings)
        collector.walk(Parser.parse(source: source))

        let aliases = KeyAliases(declarations: collector.aliasDeclarations,
                                  knownModules: collector.importedModules)
        let rewriter = AliasRewriter(aliases: aliases)
        // Mirrors CodeGenerator: registrations the emitter cannot spell are
        // dropped before anything asks which provider backs their key.
        let gate = GenericGate.admitted(rewriter.rewrite(types: collector.types))
        let resolution = ProviderResolver(
            types: gate.types,
            aliases: aliases,
            keyDisplayNames: rewriter.rewrite(keyDisplayNames: collector.keyDisplayNames)
        ).resolve()
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
        let importedValues = ImportedValueMerger(
            records: rewriter.rewrite(importedValues: collector.importedValues)
        ).merged(into: rewriter.rewrite(values: collector.values))
        let output = GeneratorOutputBuilder(
            values: importedValues.values,
            resolutions: resolution.resolutions,
            primaryResolutions: KeyIndex(imports.primaries),
            moduleAccessLevels: collector.moduleAccessLevels,
            injectedUses: rewriter.rewrite(injectedUses: collector.injectedUses),
            markedMembers: rewriter.rewrite(markedMembers: collector.markedMembers),
            keyDisplayNames: rewriter.rewrite(keyDisplayNames: collector.keyDisplayNames),
            importedModules: collector.importedModules,
            moduleImportConditions: collector.moduleImportConditions,
            primaryVariants: resolution.primaryVariants
        ).build()

        // Accumulated rather than summed in one expression: a six-way `+` chain
        // of arrays trips the type-checker's complexity limit.
        var diagnostics: [CodegenDiagnostic] = collector.diagnostics
        diagnostics += gate.diagnostics
        diagnostics += resolution.diagnostics
        diagnostics += imports.diagnostics
        diagnostics += importedValues.diagnostics
        diagnostics += output.diagnostics
        return (output, diagnostics)
    }

    // MARK: - Compilation

    private static func compile(source: String,
                                generated: String,
                                options: Options) throws -> Result {
        guard let swiftc = swiftcURL else {
            return Result(generated: generated, didCompile: false, compilerOutput: "", skipped: true)
        }

        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("zerk-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fixtureURL = directory.appendingPathComponent("Fixture.swift")
        let generatedURL = directory.appendingPathComponent("Zerk.generated.swift")

        try (preamble + "\n" + stripZerkMacros(from: source)).write(to: fixtureURL, atomically: true, encoding: .utf8)
        try standalone(generated).write(to: generatedURL, atomically: true, encoding: .utf8)

        var arguments = [
            "-typecheck",
            "-swift-version", options.swiftVersion,
            fixtureURL.path,
            generatedURL.path
        ]
        if let isolation = options.defaultActorIsolation {
            arguments += ["-default-isolation", isolation]
        }
        arguments += options.extraFlags

        let invocation = try shell(swiftc, arguments)

        // Older toolchains do not know `-default-isolation`. Report the case as
        // unverified rather than as a failure of the code under test.
        if invocation.status != 0,
           invocation.output.contains("unknown argument")
            || invocation.output.contains("unsupported option") {
            return Result(
                generated: generated,
                didCompile: false,
                compilerOutput: invocation.output,
                skipped: true
            )
        }

        return Result(
            generated: generated,
            didCompile: invocation.status == 0,
            compilerOutput: invocation.output,
            skipped: false
        )
    }

    /// `Zerk<Injectable>` and the `@injected` wrapper, so fixtures type-check
    /// without a build of the Zerk module. The Zerk macros are attribute-only
    /// markers, so stripping them changes nothing the compiler needs to see.
    ///
    /// The generic parameter's *name* is load-bearing, not cosmetic: generated
    /// code may constrain it (`where Injectable == …`), and it shadows any
    /// module type spelled the same. Keep it in step with Sources/Zerk/Zerk.swift.
    ///
    /// The interjection surface is spelled `nonisolated` **explicitly**. The real
    /// `Zerk` module is built without an ambient default, so its declarations are
    /// nonisolated whatever the consumer sets — but this preamble is compiled
    /// *with* the fixture's own flags, so under `-default-isolation MainActor` an
    /// unannotated declaration here would become `@MainActor` and no real module
    /// ever would. Without this, any fixture with a nonisolated member is
    /// unverifiable under an ambient default.
    private static let preamble = """
    // Generated test scaffolding.
    public enum Zerk<Injectable> {}

    // The interjection surface the generated file expects. Mirrors the real
    // Zerk module's shape closely enough to type-check: the namespace the
    // plugin extends per key, and the lookup every member calls. Always `nil`
    // here — this fixture proves the emitted code *compiles*, and interjection
    // behaviour is covered against the real module in ZerkTests.
    public extension Zerk {
        enum Interjection {}
        nonisolated static func _$interjected(for keyPath: KeyPath<Interjection, Void>) -> Injectable? { nil }
        nonisolated static func _$interjected() -> Injectable? { nil }
    }

    // The scoping surface, mirroring Sources/Zerk/Scoping. `nonisolated` on
    // every member for the same reason as above: the real Zerk module is built
    // without an ambient default, so a fixture compiled under
    // `-default-isolation MainActor` must not turn these isolated when no real
    // module ever would. `value` builds unconditionally — this fixture proves
    // the emitted code *compiles*, and the caching behaviour is covered against
    // the real module in ZerkTests.
    public struct InjectionScope: Hashable, Sendable {
        nonisolated public let name: String
        nonisolated public init(_ name: String) { self.name = name }
    }

    public final class ZerkScopedBox<Value>: @unchecked Sendable {
        nonisolated public let scope: InjectionScope
        nonisolated public init(scope: InjectionScope) { self.scope = scope }
        nonisolated public func value(_ build: () -> Value) -> Value { build() }
    }

    @propertyWrapper
    public struct injected<Value> {
        public var wrappedValue: Value
        public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
    }

    @propertyWrapper
    public struct autoinjected<Value> {
        public var wrappedValue: Value
        public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
    }

    @propertyWrapper
    public struct noninjected<Value> {
        public var wrappedValue: Value
        public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
    }

    @propertyWrapper
    public struct injectable<Value> {
        public var wrappedValue: Value
        public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
    }
    """

    // Prefix matches, so "@Injectable" also covers "@InjectableValue",
    // "@InjectableValues" and "@InjectableProviding" — and "@Injected" covers
    // "@InjectedDynamically".
    private static let zerkAttributePrefixes = [
        "@Injectable", "@NonInjectable", "@Singleton", "@ImportedInjectable",
        "@Isolated", "@Injected", "@Scoped"
    ]

    private static func stripZerkMacros(from source: String) -> String {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !zerkAttributePrefixes.contains { trimmed.hasPrefix($0) }
            }
            .joined(separator: "\n")
    }

    /// Removes `import Zerk` and the generated `macro Injected` declarations,
    /// which need the macro plugin to resolve.
    private static func standalone(_ generated: String) -> String {
        var keep: [String] = []
        var lines = generated.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "import Zerk" {
                index += 1
                continue
            }
            // Both roles: the stored `@Injected` variants are peer macros, the
            // `InjectedDynamically` ones are accessor macros. Missing the second kind would
            // leave a bare `macro InjectedDynamically() = #externalMacro(…)`
            // in the file, which needs the plugin this harness does not load.
            if trimmed.hasPrefix("@attached(peer") || trimmed.hasPrefix("@attached(accessor") {
                // Skip the attribute and the `macro Injected...` line after it.
                index += 2
                continue
            }
            keep.append(line)
            index += 1
        }

        lines = keep
        return lines.joined(separator: "\n")
    }

    // MARK: - Process helpers

    private static let swiftcURL: URL? = {
        for candidate in ["/usr/bin/swiftc", "/usr/local/bin/swiftc"] {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        if let resolved = try? shell(URL(fileURLWithPath: "/usr/bin/env"), ["which", "swiftc"]),
           resolved.status == 0 {
            let path = resolved.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }()

    private static func shell(_ executable: URL, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
