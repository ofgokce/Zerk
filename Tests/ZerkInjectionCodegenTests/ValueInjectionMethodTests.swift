//
//  ValueInjectionMethodTests.swift
//  Zerk
//

import Testing
import SwiftParser
@testable import CodegenToolkit

/// Values can be *copied* — the declaration's body inlined into the generated
/// member — or *referenced*, reading through to the declaration so runtime
/// updates propagate.
///
/// The referenced case is where the subtleties live: a member of a type is
/// qualified as `Type.member`, but a top-level declaration cannot be named
/// directly from inside `extension Zerk<T>` without resolving to the generated
/// member itself and recursing, so it goes through a file-scope thunk.
@Suite("Value injection methods")
struct ValueInjectionMethodTests {

    private func settings(_ method: ValueInjectionMethod) -> ZerkSettings {
        var settings = ZerkSettings.default
        settings.valueInjectionMethod = method
        return settings
    }

    private func collect(_ source: String, settings: ZerkSettings = .default) -> SourceCollector {
        let collector = SourceCollector(settings: settings)
        collector.walk(Parser.parse(source: source))
        return collector
    }

    // MARK: - Method selection

    @Test("copied is the default, and inlines the body")
    func copiedIsDefault() {
        let output = CompileFixture.generate(source: """
        @InjectableValue
        var timeout: Int { 30 }
        """)

        #expect(output.contains("return 30"))
        #expect(!output.contains("_$zerk_ref_"))
    }

    @Test("an explicit method on the attribute wins over the settings default")
    func explicitMethodOverridesSettings() {
        let source = """
        enum Constants {
            @InjectableValue(.copied)
            static let retries: Int = 3
        }
        """

        let output = CompileFixture.generate(source: source, settings: settings(.referenced))

        #expect(output.contains("return 3"))
        #expect(!output.contains("Constants.retries"))
    }

    @Test("the settings default applies when the attribute says nothing")
    func settingsDefaultApplies() {
        let source = """
        enum Constants {
            @InjectableValue
            static let retries: Int = 3
        }
        """

        #expect(CompileFixture.generate(source: source, settings: settings(.referenced))
            .contains("return Constants.retries"))
        #expect(CompileFixture.generate(source: source, settings: settings(.copied))
            .contains("return 3"))
    }

    // MARK: - Referenced shape

    @Test("a referenced 'let' reads through without gaining a setter")
    func referencedLetIsReadOnly() {
        let output = CompileFixture.generate(source: """
        enum Constants {
            @InjectableValue(.referenced)
            static let retries: Int = 3
        }
        """)

        #expect(output.contains("return Constants.retries"))
        #expect(!output.contains("set {"))
    }

    @Test("a referenced settable 'var' gains a setter that writes back")
    func referencedVarIsSettable() {
        let output = CompileFixture.generate(source: """
        enum Constants {
            @InjectableValue(.referenced)
            nonisolated(unsafe) static var baseUrl: String = "a"
        }
        """)

        #expect(output.contains("get {"))
        #expect(output.contains("return Constants.baseUrl"))
        #expect(output.contains("Constants.baseUrl = newValue"))
    }

    @Test("a referenced computed 'var' with no setter stays read-only")
    func referencedComputedVarIsReadOnly() {
        let output = CompileFixture.generate(source: """
        enum Constants {
            @InjectableValue(.referenced)
            static var derived: Int { 7 }
        }
        """)

        #expect(output.contains("return Constants.derived"))
        #expect(!output.contains("set {"))
    }

    @Test("a top-level referenced value goes through a file-scope thunk")
    func topLevelReferencedUsesThunk() {
        let output = CompileFixture.generate(source: """
        @InjectableValue(.referenced)
        nonisolated(unsafe) var timeout: Int = 30
        """)

        // A bare `timeout` inside the extension would resolve to the generated
        // member and recurse; the thunk is what makes the global reachable.
        #expect(output.contains("return _$zerk_ref_timeout()"))
        #expect(output.contains("private func _$zerk_ref_timeout() -> Int { timeout }"))
        #expect(output.contains("_$zerk_set_timeout(newValue)"))
    }

    @Test("thunks mirror the value's isolation")
    func thunksCarryIsolation() {
        let output = CompileFixture.generate(source: """
        @MainActor
        @InjectableValue(.referenced)
        var theme: String { "dark" }
        """)

        #expect(output.contains("@MainActor private func _$zerk_ref_theme() -> String { theme }"))
    }

    // MARK: - @InjectableValues

    @Test("@InjectableValues sweeps up eligible static members")
    func sweepCollectsEligibleMembers() {
        let collector = collect("""
        @InjectableValues(.referenced)
        enum AppConstants {
            static let baseUrl: String = "a"
            static let retries: Int = 3
        }
        """)

        #expect(collector.diagnostics.isEmpty)
        #expect(Set(collector.values.map(\.name)) == ["baseUrl", "retries"])
        #expect(collector.values.allSatisfy { $0.injectionMethod == .referenced })
        #expect(collector.values.allSatisfy { $0.enclosingTypePath == "AppConstants" })
    }

    @Test("@NonInjectable opts a member out of the sweep")
    func nonInjectableOptsOut() {
        let collector = collect("""
        @InjectableValues
        enum AppConstants {
            static let baseUrl: String = "a"

            @NonInjectable
            static let buildStamp: String = "b"
        }
        """)

        #expect(collector.values.map(\.name) == ["baseUrl"])
    }

    @Test("the sweep skips what it cannot inject")
    func sweepSkipsIneligibleMembers() {
        let collector = collect("""
        @InjectableValues
        enum AppConstants {
            static let visible: String = "a"
            private static let secret: String = "b"
            fileprivate static let alsoHidden: String = "c"
            let instanceProperty: String = "d"
        }
        """)

        // private/fileprivate are unreachable from the generated file, and an
        // instance property has no instance to read from.
        #expect(collector.values.map(\.name) == ["visible"])
        #expect(collector.diagnostics.isEmpty)
    }

    @Test("a swept member without a type annotation is reported, not skipped")
    func sweepRequiresTypeAnnotation() {
        let collector = collect("""
        @InjectableValues
        enum AppConstants {
            static let retries = 3
        }
        """)

        // The annotation *is* the injection key, so silently dropping the
        // member would be more surprising than refusing.
        #expect(collector.values.isEmpty)
        #expect(collector.diagnostics.contains { $0.message.contains("explicit type") })
    }

    @Test("a member's own @Injectable overrides the sweep's method")
    func memberOverridesSweepMethod() {
        let collector = collect("""
        @InjectableValues(.referenced)
        enum AppConstants {
            static let referencedOne: Int = 1

            @InjectableValue(.copied)
            static let copiedOne: Int = 2
        }
        """)

        let byName = Dictionary(uniqueKeysWithValues: collector.values.map { ($0.name, $0) })
        #expect(byName["referencedOne"]?.injectionMethod == .referenced)
        #expect(byName["copiedOne"]?.injectionMethod == .copied)
    }

    @Test("the sweep does not reach into nested types")
    func sweepDoesNotRecurse() {
        let collector = collect("""
        @InjectableValues
        enum Outer {
            static let outerValue: String = "a"

            enum Inner {
                static let innerValue: String = "b"
            }
        }
        """)

        #expect(collector.values.map(\.name) == ["outerValue"])
    }

    // MARK: - Diagnostics

    @Test("a private value cannot be referenced")
    func privateValueCannotBeReferenced() {
        let collector = collect("""
        enum Constants {
            @InjectableValue(.referenced)
            private static let secret: String = "s"
        }
        """)

        #expect(collector.values.isEmpty)
        #expect(collector.diagnostics.contains { $0.message.contains("cannot reference it") })
    }

    @Test("a private value can still be copied")
    func privateValueCanBeCopied() {
        let collector = collect("""
        enum Constants {
            @InjectableValue(.copied)
            private static let secret: String = "s"
        }
        """)

        // Copying inlines the body, so the source's visibility never matters.
        #expect(collector.values.map(\.name) == ["secret"])
        #expect(collector.diagnostics.isEmpty)
    }

    // MARK: - Compilation

    @Test("a referenced graph type-checks", arguments: ["6", "5"])
    func referencedGraphCompiles(swiftVersion: String) throws {
        let source = """
        enum AppConstants {
            nonisolated(unsafe) static var baseUrl: String = "a"
            static let retries: Int = 3
        }

        @InjectableValues(.referenced)
        enum Mirror2 {
            nonisolated(unsafe) static var mutable: String = "m"
            static let constant: Int = 1
        }
        """

        var options = swiftVersion == "6"
            ? CompileFixture.Options.swift6(defaultIsolation: nil)
            : CompileFixture.Options.swift5(defaultIsolation: nil)
        options.settings.valueInjectionMethod = .referenced

        let result = try CompileFixture.run(source: source, options: options)
        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(result.didCompile, Comment(rawValue: result.compilerOutput + "\n\n" + result.generated))
    }

    @Test("a top-level referenced value type-checks through its thunk")
    func topLevelReferencedCompiles() throws {
        let source = """
        @InjectableValue(.referenced)
        nonisolated(unsafe) var timeout: Int = 30
        """

        let result = try CompileFixture.run(source: source, options: .swift6(defaultIsolation: nil))
        try #require(!result.skipped, "no usable Swift compiler; case not verified")
        #expect(result.didCompile, Comment(rawValue: result.compilerOutput + "\n\n" + result.generated))
    }
}
