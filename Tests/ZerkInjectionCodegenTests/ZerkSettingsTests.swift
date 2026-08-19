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

    /// Every typed key against every JSON shape, because the type guards were
    /// porous in a way no amount of care at one call site would have caught.
    ///
    /// `JSONSerialization` returns booleans as `__NSCFBoolean`, which bridges to
    /// `Bool` *and* to `NSNumber` — so `true as? Int` is `1`, `1 as? Bool` is
    /// `true`, and `is Bool` answers true for both. Three guards that read
    /// correctly were therefore not holding: `"version": true` passed as version
    /// 1, `"swiftVersion": true` read as Swift 5, and
    /// `"isolatedDefaultValues": 1` silently turned off a capability gate the
    /// target genuinely needed.
    ///
    /// A grid rather than a case per bug: the language was the defect, so any
    /// key with the wrong shape could have had it, and only enumerating the
    /// shapes shows which do.
    struct Shape {
        let name: String
        let json: String
        let isAccepted: Bool

        static let all: [Shape] = [
            // version — a number, and nothing that merely bridges to one.
            Shape(name: "version: 1", json: #"{"version": 1}"#, isAccepted: true),
            Shape(name: "version: true", json: #"{"version": true}"#, isAccepted: false),
            Shape(name: #"version: "2""#, json: #"{"version": "2"}"#, isAccepted: false),
            Shape(name: "version: [2]", json: #"{"version": [2]}"#, isAccepted: false),
            Shape(name: "version: 1.5", json: #"{"version": 1.5}"#, isAccepted: false),
            Shape(name: "version: object", json: #"{"version": {"major": 2}}"#, isAccepted: false),

            // swiftVersion — a string, or a bare number for `"swiftVersion": 6`.
            Shape(name: #"swiftVersion: "6.2""#, json: #"{"swiftVersion": "6.2"}"#, isAccepted: true),
            Shape(name: "swiftVersion: 6", json: #"{"swiftVersion": 6}"#, isAccepted: true),
            Shape(name: "swiftVersion: true", json: #"{"swiftVersion": true}"#, isAccepted: false),
            Shape(name: "swiftVersion: []", json: #"{"swiftVersion": []}"#, isAccepted: false),

            // isolatedDefaultValues — a boolean, and only a boolean.
            Shape(name: "isolatedDefaultValues: true",
                  json: #"{"isolatedDefaultValues": true}"#, isAccepted: true),
            Shape(name: "isolatedDefaultValues: false",
                  json: #"{"isolatedDefaultValues": false}"#, isAccepted: true),
            Shape(name: "isolatedDefaultValues: 1",
                  json: #"{"isolatedDefaultValues": 1}"#, isAccepted: false),
            Shape(name: "isolatedDefaultValues: 0",
                  json: #"{"isolatedDefaultValues": 0}"#, isAccepted: false),
            Shape(name: #"isolatedDefaultValues: "true""#,
                  json: #"{"isolatedDefaultValues": "true"}"#, isAccepted: false),

            // The string-typed keys, for completeness of the grid.
            Shape(name: #"defaultActorIsolation: "MainActor""#,
                  json: #"{"defaultActorIsolation": "MainActor"}"#, isAccepted: true),
            Shape(name: "defaultActorIsolation: true",
                  json: #"{"defaultActorIsolation": true}"#, isAccepted: false),
            Shape(name: "defaultActorIsolation: 1",
                  json: #"{"defaultActorIsolation": 1}"#, isAccepted: false),
            Shape(name: #"strictConcurrency: "complete""#,
                  json: #"{"strictConcurrency": "complete"}"#, isAccepted: true),
            Shape(name: "strictConcurrency: 1",
                  json: #"{"strictConcurrency": 1}"#, isAccepted: false),
            Shape(name: "strictConcurrency: true",
                  json: #"{"strictConcurrency": true}"#, isAccepted: false),
            Shape(name: #"valueInjectionMethod: "referenced""#,
                  json: #"{"valueInjectionMethod": "referenced"}"#, isAccepted: true),
            Shape(name: "valueInjectionMethod: true",
                  json: #"{"valueInjectionMethod": true}"#, isAccepted: false),
        ]
    }

    @Test("each key accepts its own type and nothing that merely bridges to it",
          arguments: Shape.all)
    func typeGuardsHold(shape: Shape) throws {
        let path = write(shape.json)
        if shape.isAccepted {
            #expect(throws: Never.self) { try ZerkSettings.load(contentsOfFile: path) }
        } else {
            #expect(throws: ZerkSettings.LoadFailure.self) {
                try ZerkSettings.load(contentsOfFile: path)
            }
        }
    }

    /// The consequence, stated as itself: the capability gate must not move
    /// because a boolean was written as a number, in either direction.
    @Test("the SE-0411 gate is not moved by a bridged value")
    func capabilityGateIsNotMovedByBridging() throws {
        let enabled = try ZerkSettings.load(
            contentsOfFile: write(#"{"swiftVersion": "5", "isolatedDefaultValues": true}"#))
        #expect(enabled.supportsIsolatedDefaultValues)

        let disabled = try ZerkSettings.load(
            contentsOfFile: write(#"{"swiftVersion": "5", "isolatedDefaultValues": false}"#))
        #expect(!disabled.supportsIsolatedDefaultValues)

        // `1` used to arrive here as `true` and silently enable the gate.
        #expect(throws: ZerkSettings.LoadFailure.self) {
            try ZerkSettings.load(
                contentsOfFile: write(#"{"swiftVersion": "5", "isolatedDefaultValues": 1}"#))
        }
        // And `true` used to arrive as swiftVersion "1", turning a Swift 6
        // target into a Swift 5 one and inventing an error for it.
        #expect(throws: ZerkSettings.LoadFailure.self) {
            try ZerkSettings.load(contentsOfFile: write(#"{"swiftVersion": true}"#))
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

extension ZerkSettingsTests.Shape: CustomTestStringConvertible {
    var testDescription: String { name }
}
