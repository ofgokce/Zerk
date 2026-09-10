//
//  XcodeSettingsImport.swift
//  Zerk
//

import Foundation

/// Turns one target's Xcode build settings into a `ZerkSettings.json`.
///
/// `ZerkSettings.json` exists because a build-tool plugin cannot read the
/// target's build settings — the plugin API hands it sources and nothing else,
/// and `XcodeTarget` vends `displayName`, `product`, `dependencies` and
/// `inputFiles` with no settings among them. So the facts have to be restated,
/// and restating them by hand is where they drift: the file says
/// `"defaultActorIsolation": "nonisolated"` while the target has been switched
/// to `MainActor`, and Zerk then infers the wrong isolation for every provider.
///
/// `xcodebuild -showBuildSettings` *can* read them, which is the one route
/// available. This maps its output onto the four keys that mirror a build
/// setting, and leaves the fifth — `valueInjectionMethod` — alone, because it
/// mirrors nothing and is the developer's own choice.
///
/// A setting the target does not set is **absent** from that output rather than
/// reported with a default, which lines up exactly with this file's optional
/// keys: absent there becomes omitted here, and Zerk's own default takes over.
public enum XcodeSettingsImport {

    public struct Failure: Error {
        public let message: String
    }

    /// The file this writes, named here because `ZerkSettings` is internal to
    /// this module and the tool that writes the file is not in it.
    public static let settingsFileName = ZerkSettings.fileName

    /// Build settings Zerk mirrors, and the key each becomes.
    ///
    /// `SWIFT_APPROACHABLE_CONCURRENCY` is deliberately absent. It turns on a
    /// *set* of upcoming features, and which ones is a property of the compiler
    /// rather than of anything readable here — mapping it would mean asserting
    /// that the set contains `IsolatedDefaultValues`, which is exactly the kind
    /// of guess this file exists to remove. A target using it still states
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION` explicitly, which is read below.
    static let swiftVersionKey = "SWIFT_VERSION"
    static let strictConcurrencyKey = "SWIFT_STRICT_CONCURRENCY"
    static let defaultActorIsolationKey = "SWIFT_DEFAULT_ACTOR_ISOLATION"
    static let isolatedDefaultValuesKey = "SWIFT_UPCOMING_FEATURE_ISOLATED_DEFAULT_VALUES"

    /// One entry of `xcodebuild -showBuildSettings -json`.
    private struct Entry: Decodable {
        var target: String?
        var buildSettings: [String: String]
    }

    /// The settings for `target`, or for the only target when none is named.
    ///
    /// `xcodebuild` reports one entry per target, so a project with several
    /// needs to be told which — picking the first would answer confidently
    /// about the wrong one.
    static func settings(fromShowBuildSettings data: Data,
                         target: String?) throws -> (name: String, values: [String: String]) {
        let entries: [Entry]
        do {
            entries = try JSONDecoder().decode([Entry].self, from: data)
        } catch {
            throw Failure(message: "could not read xcodebuild's output: \(error)")
        }

        guard !entries.isEmpty else {
            throw Failure(message: "xcodebuild reported no targets. Check --project and --target.")
        }

        if let target {
            guard let entry = entries.first(where: { $0.target == target }) else {
                let known = entries.compactMap(\.target).sorted().joined(separator: ", ")
                throw Failure(
                    message: "xcodebuild reported no target named '\(target)'."
                        + (known.isEmpty ? "" : " It reported: \(known).")
                )
            }
            return (target, entry.buildSettings)
        }

        guard entries.count == 1 else {
            let known = entries.compactMap(\.target).sorted().joined(separator: ", ")
            throw Failure(
                message: "this project has several targets — name one with --target. It has: \(known)."
            )
        }
        return (entries[0].target ?? "", entries[0].buildSettings)
    }

    /// The `ZerkSettings.json` for one target's build settings.
    ///
    /// The result is parsed back through ``ZerkSettings/load(contentsOfFile:)``'s
    /// own decoding before it is returned, so this can only emit a file Zerk can
    /// read. A rendering mistake becomes an error here rather than a settings
    /// file that fails at the next build.
    public static func settingsFile(fromShowBuildSettings data: Data,
                                    target: String?) throws -> (contents: String, target: String) {
        let (name, values) = try settings(fromShowBuildSettings: data, target: target)
        let contents = try render(values, target: name)

        do {
            _ = try ZerkSettings.decode(json: ZerkSettings.stripComments(from: contents))
        } catch {
            throw Failure(
                message: "produced a settings file Zerk cannot read, which is a bug in Zerk: \(error)"
            )
        }

        return (contents, name)
    }

    private static func render(_ values: [String: String], target: String) throws -> String {
        var lines: [String] = [
            "{",
            "  // Generated by 'swift package zerk settings' from the build settings of",
            "  // target '\(target)'. Re-run it when those change.",
            "  //",
            "  // Only the keys that mirror a build setting are written. Anything the",
            "  // target does not set is left out, so Zerk's own default applies.",
            "",
            "  \"version\": 1,",
        ]

        if let isolation = values[defaultActorIsolationKey], !isolation.isEmpty {
            lines += [
                "",
                "  // \(defaultActorIsolationKey)",
                "  \"defaultActorIsolation\": \(quoted(isolation)),",
            ]
        }

        if let version = values[swiftVersionKey], !version.isEmpty {
            lines += [
                "",
                "  // \(swiftVersionKey)",
                "  \"swiftVersion\": \(quoted(version)),",
            ]
        }

        if let concurrency = values[strictConcurrencyKey], !concurrency.isEmpty {
            guard ZerkSettings.StrictConcurrency(rawValue: concurrency) != nil else {
                throw Failure(
                    message: "\(strictConcurrencyKey) is '\(concurrency)', which is not one of "
                        + "\"minimal\", \"targeted\" or \"complete\"."
                )
            }
            lines += [
                "",
                "  // \(strictConcurrencyKey)",
                "  \"strictConcurrency\": \(quoted(concurrency)),",
            ]
        }

        if let feature = values[isolatedDefaultValuesKey], !feature.isEmpty {
            guard let flag = booleanSetting(feature) else {
                throw Failure(
                    message: "\(isolatedDefaultValuesKey) is '\(feature)', which is not YES or NO."
                )
            }
            lines += [
                "",
                "  // \(isolatedDefaultValuesKey)",
                "  \"isolatedDefaultValues\": \(flag),",
            ]
        }

        // Every key above is written with a trailing comma so the order can
        // change without a special case; JSON has no trailing comma, so the last
        // one comes back off here.
        if let last = lines.last, last.hasSuffix(",") {
            lines[lines.count - 1] = String(last.dropLast())
        }
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Xcode writes booleans as `YES`/`NO`; a value edited by hand may well say
    /// `true`. Both are read, and nothing else is guessed at.
    private static func booleanSetting(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "yes", "true": return true
        case "no", "false": return false
        default: return nil
        }
    }

    private static func quoted(_ value: String) -> String {
        // Through `JSONEncoder` rather than by wrapping in quotes: a global
        // actor's name is an identifier today, and hand-rolled escaping is how
        // that stops being true quietly.
        guard let data = try? JSONEncoder().encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return "\"\(value)\""
        }
        return text
    }
}
