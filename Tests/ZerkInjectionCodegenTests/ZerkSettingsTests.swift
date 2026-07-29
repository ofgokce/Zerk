//
//  ZerkSettingsTests.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 28.07.2026.
//

import Foundation
import Testing
@testable import CodegenToolkit

@Suite("ZerkSettings")
struct ZerkSettingsTests {

    @Test("line comments are stripped")
    func lineCommentsAreStripped() {
        let source = """
        {
          // a comment
          "version": 1, // trailing comment
          "defaultActorIsolation": "MainActor"
        }
        """

        let settings = try? ZerkSettings.load(contentsOfFile: write(source))
        #expect(settings?.defaultActorIsolation == .globalActor("MainActor"))
    }

    @Test("block comments are stripped")
    func blockCommentsAreStripped() {
        let source = """
        {
          /* a
             multi-line
             comment */
          "swiftVersion": "6"
        }
        """

        let settings = try? ZerkSettings.load(contentsOfFile: write(source))
        #expect(settings?.swiftVersion == "6")
    }

    @Test("a slash pair inside a string literal is preserved")
    func slashesInsideStringsSurvive() {
        // A naive stripper would truncate the value at "//" and produce
        // invalid JSON.
        let source = """
        {
          "defaultActorIsolation": "https://example.com/NotAnActor"
        }
        """

        let settings = try? ZerkSettings.load(contentsOfFile: write(source))
        #expect(settings?.defaultActorIsolation == .globalActor("https://example.com/NotAnActor"))
    }

    @Test("an escaped quote does not end the string early")
    func escapedQuotesAreHonoured() {
        let stripped = ZerkSettings.stripComments(from: #"{"a": "x\"// y", "b": 1}"#)
        #expect(stripped == #"{"a": "x\"// y", "b": 1}"#)
    }

    @Test("nonisolated is the default when the file is absent")
    func defaultsWhenAbsent() throws {
        let settings = try ZerkSettings.load(searchPaths: ["/nonexistent-zerk-path"])
        #expect(settings == .default)
        #expect(settings.defaultActorIsolation == .nonisolated)
    }

    @Test("a future schema version is rejected")
    func futureVersionRejected() {
        let path = write(#"{"version": 999}"#)
        #expect(throws: ZerkSettings.LoadFailure.self) {
            try ZerkSettings.load(contentsOfFile: path)
        }
    }

    @Test("swift 5 is recognised as pre-6")
    func swift5IsRecognised() {
        var settings = ZerkSettings.default
        settings.swiftVersion = "5"
        #expect(!settings.isSwift6OrLater)
        settings.swiftVersion = "6"
        #expect(settings.isSwift6OrLater)
        settings.swiftVersion = "6.2"
        #expect(settings.isSwift6OrLater)
    }

    @Test("the reference settings file parses")
    func referenceFileParses() throws {
        // The copy at the package root is real configuration, not an example,
        // so a schema change that breaks it breaks Zerk's own build.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ZerkInjectionCodegenTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package root
            .appendingPathComponent("ZerkSettings.json")

        try #require(FileManager.default.fileExists(atPath: root.path))
        let settings = try ZerkSettings.load(contentsOfFile: root.path)
        #expect(settings.defaultActorIsolation == .nonisolated)
        #expect(settings.swiftVersion == "6")
    }

    private func write(_ contents: String) -> String {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ZerkSettings-\(UUID().uuidString).json")
        try? contents.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }
}
