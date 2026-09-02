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

        var settings = try decode(json: stripComments(from: raw), path: path)
        settings.sourcePath = path
        return settings
    }

    /// Parses the file's text, comments already stripped.
    ///
    /// Split from ``load(contentsOfFile:)`` so that whatever *writes* a settings
    /// file can read its own output back through the same parser — see
    /// ``XcodeSettingsImport``. `path` only names the file in diagnostics, so a
    /// caller holding text rather than a file passes what it has.
    static func decode(json: String, path: String = fileName) throws -> ZerkSettings {
        guard let data = json.data(using: .utf8) else {
            throw LoadFailure(message: "\(fileName) is not valid UTF-8.", path: path)
        }

        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch let malformed as MalformedKey {
            throw LoadFailure(message: malformed.message, path: path)
        } catch DecodingError.typeMismatch(_, let context) where context.codingPath.isEmpty {
            // Valid JSON of the wrong shape — an array, a string, a bare number
            // at the top level. A mismatch *inside* the object is a key's
            // problem, and `Payload` has already reported that one by name, so
            // an empty coding path is what says the file itself is wrong.
            throw LoadFailure(message: "\(fileName) must contain a JSON object.", path: path)
        } catch {
            throw LoadFailure(
                message: "\(fileName) is not valid JSON: \(error.localizedDescription)",
                path: path
            )
        }

        // Checked before anything else is read: this is the key that decides
        // whether the rest can be trusted to mean what they say. Written as
        // `"version": "2"` it used to fail a cast and skip the guard, so a
        // settings file from a newer Zerk was read as if it were current.
        if let version = payload.version {
            guard version <= currentVersion else {
                throw LoadFailure(
                    message: "\(fileName) declares version \(version); this version of Zerk understands up to \(currentVersion).",
                    path: path
                )
            }
        }

        var settings = ZerkSettings.default

        if let text = payload.defaultActorIsolation {
            switch text {
            case "nonisolated":
                settings.defaultActorIsolation = .nonisolated
            case "":
                throw LoadFailure(message: "'defaultActorIsolation' must not be empty.", path: path)
            default:
                settings.defaultActorIsolation = .globalActor(text)
            }
        }

        if let text = payload.swiftVersion {
            settings.swiftVersion = text
        }

        if let text = payload.valueInjectionMethod {
            guard let resolved = ValueInjectionMethod(rawValue: text) else {
                throw LoadFailure(
                    message: "'valueInjectionMethod' must be \"copied\" or \"referenced\"; found \"\(text)\".",
                    path: path
                )
            }
            settings.valueInjectionMethod = resolved
        }

        if let text = payload.strictConcurrency {
            guard let level = StrictConcurrency(rawValue: text) else {
                throw LoadFailure(
                    message: "'strictConcurrency' must be \"minimal\", \"targeted\", or \"complete\"; found \"\(text)\".",
                    path: path
                )
            }
            settings.strictConcurrency = level
        }

        if let flag = payload.isolatedDefaultValues {
            settings.isolatedDefaultValues = flag
        }

        return settings
    }

    /// A key that is present and not the type it has to be. Carries only the
    /// message, because `Decodable` has no idea which file it is reading;
    /// ``load(contentsOfFile:)`` adds the path.
    struct MalformedKey: Error {
        let message: String
    }

    /// The settings file's shape, **decoded** rather than deserialized into
    /// `Any` and cast.
    ///
    /// The casts this replaces could not tell a JSON boolean from a JSON number
    /// in either direction — measured, not assumed: for `{"a": true, "b": 1}`,
    /// `a is Bool` and `b is Bool` are both true, `a as? Int` is `1` and
    /// `b as? Bool` is `true`. Distinguishing them needed
    /// `CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID()`, since the
    /// CoreFoundation type is the only thing that differed.
    ///
    /// That was not cosmetic — it moved the SE-0411 capability gate *both* ways
    /// on the same source: `"isolatedDefaultValues": 1` silently disabled a
    /// warning the target genuinely needed, and `"swiftVersion": true` read as
    /// Swift 5 and produced one it did not.
    ///
    /// `JSONDecoder` draws the distinction itself, in the language rather than
    /// in the Objective-C runtime: `true` decodes as `Bool` and refuses `Int`,
    /// `1` decodes as `Int` and refuses `Bool`. That deletes the CoreFoundation
    /// call, which is also the one thing in Zerk that Darwin alone could answer
    /// — `JSONSerialization` on Linux returns a plain `NSNumber` for a JSON
    /// boolean, so the check would have compiled there and quietly said no.
    ///
    /// Unknown keys are ignored, as `Decodable` ignores them, so a file written
    /// for a newer Zerk still loads.
    private struct Payload: Decodable {
        var version: Int?
        var defaultActorIsolation: String?
        var swiftVersion: String?
        var valueInjectionMethod: String?
        var strictConcurrency: String?
        var isolatedDefaultValues: Bool?

        enum CodingKeys: String, CodingKey {
            case version
            case defaultActorIsolation
            case swiftVersion
            case valueInjectionMethod
            case strictConcurrency
            case isolatedDefaultValues
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            version = try container.zerkValue(Int.self, forKey: .version, mustBe: "a number")
            defaultActorIsolation = try container.zerkValue(
                String.self, forKey: .defaultActorIsolation, mustBe: "a string")
            valueInjectionMethod = try container.zerkValue(
                String.self, forKey: .valueInjectionMethod, mustBe: "a string")
            strictConcurrency = try container.zerkValue(
                String.self, forKey: .strictConcurrency, mustBe: "a string")
            isolatedDefaultValues = try container.zerkValue(
                Bool.self, forKey: .isolatedDefaultValues, mustBe: "a boolean")

            // The one key with two spellings: a bare number is accepted because
            // `"swiftVersion": 6` is the obvious thing to write. A boolean is
            // not, and used to arrive here as `1` and read as Swift 5.
            if container.contains(.swiftVersion) {
                if let text = try? container.decode(String.self, forKey: .swiftVersion) {
                    swiftVersion = text
                } else if let number = try? container.decode(Int.self, forKey: .swiftVersion) {
                    swiftVersion = String(number)
                } else {
                    throw MalformedKey(message: "'swiftVersion' must be a string.")
                }
            }
        }
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

private extension KeyedDecodingContainer {

    /// Decodes `key`, or reports that it is present and the wrong type.
    ///
    /// Absent is `nil` rather than an error, since every key is optional. Present
    /// and undecodable is a `MalformedKey` naming the key and the type it has to
    /// be, so the message reads the way the hand-written casts used to.
    func zerkValue<T: Decodable>(_ type: T.Type,
                                 forKey key: Key,
                                 mustBe description: String) throws -> T? {
        guard contains(key) else { return nil }
        guard let value = try? decode(T.self, forKey: key) else {
            throw ZerkSettings.MalformedKey(
                message: "'\(key.stringValue)' must be \(description).")
        }
        return value
    }
}
