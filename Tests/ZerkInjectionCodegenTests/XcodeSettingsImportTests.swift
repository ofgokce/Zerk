//
//  XcodeSettingsImportTests.swift
//  Zerk
//

import Foundation
import Testing
@testable import CodegenToolkit

/// `swift package zerk settings` reads a target's build settings and writes the
/// `ZerkSettings.json` that matches them, which is the drift this file exists to
/// remove: the settings file says `nonisolated` while the target has been moved
/// to `MainActor`, and Zerk then infers the wrong isolation for every provider.
///
/// Everything here works on a recorded `xcodebuild -showBuildSettings -json`
/// shape rather than by running Xcode, so the mapping is testable on any
/// machine. That the real output has this shape — and that the four settings
/// appear in it at all — was checked against a project before any of this was
/// written.
@Suite("Xcode settings import")
struct XcodeSettingsImportTests {

    /// One `xcodebuild` entry, as its `-json` output spells it.
    private func dump(_ targets: [(name: String, settings: [String: String])]) -> Data {
        let entries = targets.map { target in
            ["target": target.name, "buildSettings": target.settings] as [String: Any]
        }
        return try! JSONSerialization.data(withJSONObject: entries)
    }

    // MARK: - Mapping

    @Test("every mirrored setting becomes its key")
    func mirroredSettingsAreMapped() throws {
        let (contents, target) = try XcodeSettingsImport.settingsFile(
            fromShowBuildSettings: dump([("App", [
                "SWIFT_VERSION": "5.0",
                "SWIFT_STRICT_CONCURRENCY": "complete",
                "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
                "SWIFT_UPCOMING_FEATURE_ISOLATED_DEFAULT_VALUES": "YES",
            ])]),
            target: nil)

        #expect(target == "App")

        // Read back through Zerk's own parser rather than matched as text: what
        // matters is the settings the build will see, not their spelling.
        let settings = try ZerkSettings.decode(json: ZerkSettings.stripComments(from: contents))
        #expect(settings.swiftVersion == "5.0")
        #expect(settings.strictConcurrency == .complete)
        #expect(settings.defaultActorIsolation == .globalActor("MainActor"))
        #expect(settings.isolatedDefaultValues)
    }

    /// A setting the target does not set is absent from xcodebuild's output
    /// rather than reported with a default, so the key is left out and Zerk's
    /// own default applies. Writing a default instead would freeze today's
    /// default into every generated file.
    @Test("a setting the target does not set is left out")
    func unsetSettingsAreOmitted() throws {
        let (contents, _) = try XcodeSettingsImport.settingsFile(
            fromShowBuildSettings: dump([("App", ["SWIFT_VERSION": "6.0"])]),
            target: nil)

        #expect(contents.contains("\"swiftVersion\": \"6.0\""))
        #expect(!contents.contains("strictConcurrency"))
        #expect(!contents.contains("defaultActorIsolation"))
        #expect(!contents.contains("isolatedDefaultValues"))

        let settings = try ZerkSettings.decode(json: ZerkSettings.stripComments(from: contents))
        #expect(settings.strictConcurrency == .minimal)
        #expect(settings.defaultActorIsolation == .nonisolated)
        #expect(!settings.isolatedDefaultValues)
    }

    /// `valueInjectionMethod` mirrors no build setting, so there is nothing to
    /// read it from and it is never written. Stated as a test because the
    /// consequence is a real one: re-running the command does not clobber the
    /// developer's answer, and does not carry it over either.
    @Test("valueInjectionMethod is never written")
    func valueInjectionMethodIsNotWritten() throws {
        let (contents, _) = try XcodeSettingsImport.settingsFile(
            fromShowBuildSettings: dump([("App", [
                "SWIFT_VERSION": "6.0",
                "SWIFT_STRICT_CONCURRENCY": "complete",
            ])]),
            target: nil)

        #expect(!contents.contains("valueInjectionMethod"))
    }

    @Test("YES and NO are read as booleans")
    func xcodeBooleansAreRead() throws {
        for (written, expected) in [("YES", true), ("NO", false), ("true", true), ("false", false)] {
            let (contents, _) = try XcodeSettingsImport.settingsFile(
                fromShowBuildSettings: dump([("App", [
                    "SWIFT_UPCOMING_FEATURE_ISOLATED_DEFAULT_VALUES": written,
                ])]),
                target: nil)
            let settings = try ZerkSettings.decode(json: ZerkSettings.stripComments(from: contents))
            #expect(settings.isolatedDefaultValues == expected, "\(written)")
        }
    }

    // MARK: - Choosing a target

    @Test("the only target needs no --target")
    func aLoneTargetIsChosen() throws {
        let (_, target) = try XcodeSettingsImport.settingsFile(
            fromShowBuildSettings: dump([("Solo", ["SWIFT_VERSION": "6.0"])]),
            target: nil)
        #expect(target == "Solo")
    }

    /// Picking the first would answer confidently about the wrong target, and
    /// the resulting file would look entirely correct.
    @Test("several targets must be told which")
    func severalTargetsAreRefused() {
        let data = dump([("App", ["SWIFT_VERSION": "6.0"]), ("Kit", ["SWIFT_VERSION": "5.0"])])
        let failure = #expect(throws: XcodeSettingsImport.Failure.self) {
            try XcodeSettingsImport.settingsFile(fromShowBuildSettings: data, target: nil)
        }
        #expect(failure?.message.contains("App, Kit") == true)
    }

    @Test("a named target is the one read")
    func aNamedTargetIsRead() throws {
        let data = dump([("App", ["SWIFT_VERSION": "6.0"]), ("Kit", ["SWIFT_VERSION": "5.0"])])
        let (contents, target) = try XcodeSettingsImport.settingsFile(
            fromShowBuildSettings: data, target: "Kit")
        #expect(target == "Kit")
        #expect(contents.contains("\"swiftVersion\": \"5.0\""))
    }

    /// Naming the targets it does have, because that is the next thing the
    /// reader needs and xcodebuild's own answer to this is a result bundle.
    @Test("an unknown target is reported with the ones that exist")
    func anUnknownTargetNamesTheRest() {
        let data = dump([("App", [:]), ("Kit", [:])])
        let failure = #expect(throws: XcodeSettingsImport.Failure.self) {
            try XcodeSettingsImport.settingsFile(fromShowBuildSettings: data, target: "Nope")
        }
        #expect(failure?.message.contains("'Nope'") == true)
        #expect(failure?.message.contains("App, Kit") == true)
    }

    // MARK: - Values Zerk cannot use

    /// Refused rather than passed through: a settings file Zerk rejects at the
    /// next build is a worse answer than an error naming the build setting.
    @Test("a strictConcurrency Zerk does not know is refused")
    func unknownConcurrencyIsRefused() {
        let data = dump([("App", ["SWIFT_STRICT_CONCURRENCY": "aggressive"])])
        let failure = #expect(throws: XcodeSettingsImport.Failure.self) {
            try XcodeSettingsImport.settingsFile(fromShowBuildSettings: data, target: nil)
        }
        // Named as the *build setting*, not as the JSON key. The round-trip
        // check would refuse this too, one step later, with a message about
        // `strictConcurrency` — which sends the reader to the file Zerk just
        // wrote rather than to the setting that produced it.
        #expect(failure?.message.contains("SWIFT_STRICT_CONCURRENCY") == true,
                "\(failure?.message ?? "no failure")")
        #expect(failure?.message.contains("aggressive") == true)
    }

    @Test("a non-boolean upcoming-feature value is refused")
    func nonBooleanFeatureIsRefused() {
        let data = dump([("App", ["SWIFT_UPCOMING_FEATURE_ISOLATED_DEFAULT_VALUES": "MAYBE"])])
        #expect(throws: XcodeSettingsImport.Failure.self) {
            try XcodeSettingsImport.settingsFile(fromShowBuildSettings: data, target: nil)
        }
    }

    @Test("output that is not xcodebuild's is refused")
    func garbageInputIsRefused() {
        #expect(throws: XcodeSettingsImport.Failure.self) {
            try XcodeSettingsImport.settingsFile(
                fromShowBuildSettings: Data("not json".utf8), target: nil)
        }
    }

    /// A global actor's name reaches the file as a JSON string, so it is encoded
    /// rather than wrapped in quotes. Nothing Xcode produces needs escaping
    /// today, which is exactly why hand-rolled quoting would survive unnoticed
    /// until something did.
    @Test("a value needing escape is still valid JSON")
    func awkwardValuesAreEscaped() throws {
        let (contents, _) = try XcodeSettingsImport.settingsFile(
            fromShowBuildSettings: dump([("App", [
                "SWIFT_DEFAULT_ACTOR_ISOLATION": #"Weird"Actor"#,
            ])]),
            target: nil)

        let settings = try ZerkSettings.decode(json: ZerkSettings.stripComments(from: contents))
        #expect(settings.defaultActorIsolation == .globalActor(#"Weird"Actor"#))
    }

    // MARK: - The file it writes

    /// The rendered file has to survive the round trip through the real loader,
    /// comments and all — it is written to disk for a build to read, not just
    /// decoded in memory.
    @Test("the written file loads through ZerkSettings.load")
    func theWrittenFileLoads() throws {
        let (contents, _) = try XcodeSettingsImport.settingsFile(
            fromShowBuildSettings: dump([("App", [
                "SWIFT_VERSION": "5",
                "SWIFT_DEFAULT_ACTOR_ISOLATION": "nonisolated",
                "SWIFT_UPCOMING_FEATURE_ISOLATED_DEFAULT_VALUES": "YES",
            ])]),
            target: nil)

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ZerkSettings-\(UUID().uuidString).json")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let settings = try ZerkSettings.load(contentsOfFile: url.path)
        #expect(settings.swiftVersion == "5")
        #expect(settings.defaultActorIsolation == .nonisolated)
        #expect(settings.supportsIsolatedDefaultValues)
        #expect(settings.sourcePath == url.path)
    }
}
