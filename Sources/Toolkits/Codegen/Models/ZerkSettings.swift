//
//  ZerkSettings.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 28.07.2026.
//

import Foundation

/// Contents of `ZerkSettings.json`.
///
/// The build-tool plugin cannot read the target's build settings, so anything
/// Zerk needs to know about the compiler's configuration has to be restated
/// here. The file governs how Zerk *reads* source — never what it writes: every
/// generated member is pinned with explicit isolation regardless.
struct ZerkSettings: Equatable {
    static let fileName = "ZerkSettings.json"
    /// Highest `version` this build understands. A file declaring more is
    /// rejected rather than partially honored.
    static let currentVersion = 1

    /// Concurrency checking level of the target. Mirrors
    /// `SWIFT_STRICT_CONCURRENCY`. Only consulted under Swift 5 language mode —
    /// Swift 6 mode is complete checking by definition.
    enum StrictConcurrency: String, Equatable {
        case minimal
        case targeted
        case complete
    }

    /// How `@InjectableValue` declarations reach their value when the declaration says
    /// `.default`. Has no build-setting counterpart — it is Zerk's own default.
    var valueInjectionMethod: ValueInjectionMethod = .copied
    /// Ambient isolation applied to declarations that state none. Mirrors the
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION` build setting.
    var defaultActorIsolation: ProviderIsolation
    /// Language mode of the target. Mirrors `SWIFT_VERSION`.
    var swiftVersion: String
    /// Mirrors `SWIFT_STRICT_CONCURRENCY`. Defaults to the compiler's own
    /// default, `minimal`.
    var strictConcurrency: StrictConcurrency = .minimal
    /// Mirrors `SWIFT_UPCOMING_FEATURE_ISOLATED_DEFAULT_VALUES`, the opt-in for
    /// SE-0411 under Swift 5 language mode.
    var isolatedDefaultValues: Bool = false
    /// Where the settings were loaded from, for diagnostics. `nil` when
    /// defaults were used because no file was found.
    var sourcePath: String?

    static let `default` = ZerkSettings(
        valueInjectionMethod: .copied,
        defaultActorIsolation: .nonisolated,
        swiftVersion: "6",
        strictConcurrency: .minimal,
        isolatedDefaultValues: false,
        sourcePath: nil
    )

    var isSwift6OrLater: Bool {
        guard let major = Int(swiftVersion.split(separator: ".").first.map(String.init) ?? swiftVersion) else {
            // Unrecognized values are treated permissively; the compiler will
            // have the final say either way.
            return true
        }
        return major >= 6
    }

    /// Whether the target evaluates a default argument expression in the
    /// *callee's* isolation domain (SE-0411).
    ///
    /// This is the single capability that decides whether Zerk may emit a
    /// same-domain isolated default argument. Swift 6 language mode has it
    /// always; Swift 5 mode gets it from either complete strict concurrency or
    /// the `IsolatedDefaultValues` upcoming feature, independently — verified
    /// by compiling both against a 6.3 toolchain.
    ///
    /// Every other isolated construct Zerk emits compiles under stock Swift 5,
    /// so this is deliberately the only capability gate.
    var supportsIsolatedDefaultValues: Bool {
        isSwift6OrLater || strictConcurrency == .complete || isolatedDefaultValues
    }
}

extension ZerkSettings {

    /// A malformed settings file. Carries the path so the failure can be
    /// reported against the file itself.
    struct LoadFailure: Error {
        let message: String
        let path: String
    }

    /// Loads the first `ZerkSettings.json` found by walking `searchPaths` in
    /// order. Missing files are not an error — Zerk falls back to defaults,
    /// which describe a stock Swift 6 target.
    static func load(searchPaths: [String]) throws -> ZerkSettings {
        for directory in searchPaths {
            let path = (directory as NSString).appendingPathComponent(fileName)
            guard FileManager.default.fileExists(atPath: path) else {
                continue
            }
            return try load(contentsOfFile: path)
        }
        return .default
    }

    /// Parses one settings file. Unknown keys are ignored so a newer file
    /// stays loadable, but a malformed *known* key is an error rather than a
    /// silent fallback to the default.
    static func load(contentsOfFile path: String) throws -> ZerkSettings {
        let raw: String
        do {
            raw = try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            throw LoadFailure(message: "Could not read \(fileName).", path: path)
        }

        let json = stripComments(from: raw)
        guard let data = json.data(using: .utf8) else {
            throw LoadFailure(message: "\(fileName) is not valid UTF-8.", path: path)
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw LoadFailure(
                message: "\(fileName) is not valid JSON: \(error.localizedDescription)",
                path: path
            )
        }

        guard let dictionary = object as? [String: Any] else {
            throw LoadFailure(message: "\(fileName) must contain a JSON object.", path: path)
        }

        // Typed like every other key below, and for a stronger reason than any
        // of them: this is the key that decides whether the rest can be trusted
        // to mean what they say. Written as `"version": "2"` it failed the cast
        // and skipped the guard, so a settings file from a newer Zerk was read
        // as if it were current.
        if let version = dictionary["version"] {
            guard !Self.isJSONBoolean(version), let number = version as? Int else {
                throw LoadFailure(message: "'version' must be a number.", path: path)
            }
            guard number <= currentVersion else {
                throw LoadFailure(
                    message: "\(fileName) declares version \(number); this version of Zerk understands up to \(currentVersion).",
                    path: path
                )
            }
        }

        var settings = ZerkSettings.default
        settings.sourcePath = path

        if let isolation = dictionary["defaultActorIsolation"] {
            guard let text = isolation as? String else {
                throw LoadFailure(message: "'defaultActorIsolation' must be a string.", path: path)
            }
            switch text {
            case "nonisolated":
                settings.defaultActorIsolation = .nonisolated
            case "":
                throw LoadFailure(message: "'defaultActorIsolation' must not be empty.", path: path)
            default:
                settings.defaultActorIsolation = .globalActor(text)
            }
        }

        if let version = dictionary["swiftVersion"] {
            // A number is accepted because `"swiftVersion": 6` is the obvious
            // thing to write; a boolean is not, and would otherwise arrive here
            // as `1` and read as Swift 5.
            if !Self.isJSONBoolean(version), let text = version as? String {
                settings.swiftVersion = text
            } else if !Self.isJSONBoolean(version), let number = version as? Int {
                settings.swiftVersion = String(number)
            } else {
                throw LoadFailure(message: "'swiftVersion' must be a string.", path: path)
            }
        }

        if let method = dictionary["valueInjectionMethod"] {
            guard let text = method as? String else {
                throw LoadFailure(message: "'valueInjectionMethod' must be a string.", path: path)
            }
            guard let resolved = ValueInjectionMethod(rawValue: text) else {
                throw LoadFailure(
                    message: "'valueInjectionMethod' must be \"copied\" or \"referenced\"; found \"\(text)\".",
                    path: path
                )
            }
            settings.valueInjectionMethod = resolved
        }

        if let concurrency = dictionary["strictConcurrency"] {
            guard let text = concurrency as? String else {
                throw LoadFailure(message: "'strictConcurrency' must be a string.", path: path)
            }
            guard let level = StrictConcurrency(rawValue: text) else {
                throw LoadFailure(
                    message: "'strictConcurrency' must be \"minimal\", \"targeted\", or \"complete\"; found \"\(text)\".",
                    path: path
                )
            }
            settings.strictConcurrency = level
        }

        if let feature = dictionary["isolatedDefaultValues"] {
            guard Self.isJSONBoolean(feature), let flag = feature as? Bool else {
                throw LoadFailure(message: "'isolatedDefaultValues' must be a boolean.", path: path)
            }
            settings.isolatedDefaultValues = flag
        }

        return settings
    }

    /// Whether a value `JSONSerialization` produced is a JSON **boolean**.
    ///
    /// Neither `is Bool` nor `is NSNumber` answers this. `JSONSerialization`
    /// returns booleans as `__NSCFBoolean`, which bridges to both — measured,
    /// not assumed: for `{"a": true, "b": 1}`, `a is Bool` and `b is Bool` are
    /// both true, as are `a is NSNumber` and `b is NSNumber`, and `true as? Int`
    /// is `1` while `1 as? Bool` is `true`. So the casts the type guards were
    /// written as could not tell the two apart in either direction.
    ///
    /// That was not cosmetic. It moved the SE-0411 capability gate *both* ways
    /// on the same source: `"isolatedDefaultValues": 1` silently disabled a
    /// warning the target genuinely needed, and `"swiftVersion": true` read as
    /// Swift 5 and produced one it did not.
    ///
    /// The CoreFoundation type is what actually differs, so that is what this
    /// asks.
    private static func isJSONBoolean(_ value: Any) -> Bool {
        CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID()
    }

    /// JSON has no comments, but the reference settings file documents itself
    /// inline, so `//` line comments are stripped before parsing.
    ///
    /// The scan is string-aware: a `//` inside a JSON string literal (a URL,
    /// say) is left alone, and escape sequences are honoured so that a string
    /// ending in `\\` still terminates correctly.
    static func stripComments(from source: String) -> String {
        var result = ""
        result.reserveCapacity(source.count)

        var insideString = false
        var isEscaped = false
        var index = source.startIndex

        while index < source.endIndex {
            let character = source[index]

            if insideString {
                result.append(character)
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    insideString = false
                }
                index = source.index(after: index)
                continue
            }

            if character == "\"" {
                insideString = true
                result.append(character)
                index = source.index(after: index)
                continue
            }

            if character == "/" {
                let next = source.index(after: index)
                if next < source.endIndex, source[next] == "/" {
                    // Drop through to (but keep) the newline so line numbers
                    // in JSON parser errors stay meaningful.
                    while index < source.endIndex, !source[index].isNewline {
                        index = source.index(after: index)
                    }
                    continue
                }
                if next < source.endIndex, source[next] == "*" {
                    var scan = source.index(after: next)
                    while scan < source.endIndex {
                        let closing = source.index(after: scan)
                        if source[scan] == "*", closing < source.endIndex, source[closing] == "/" {
                            scan = source.index(after: closing)
                            break
                        }
                        if source[scan].isNewline {
                            result.append("\n")
                        }
                        scan = source.index(after: scan)
                    }
                    index = scan
                    continue
                }
            }

            result.append(character)
            index = source.index(after: index)
        }

        return result
    }
}
