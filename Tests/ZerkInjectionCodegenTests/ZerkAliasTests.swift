//
//  ZerkAliasTests.swift
//  Zerk
//

import SwiftParser
import Testing
@testable import CodegenToolkit

/// Coverage of `@ZerkAlias` / `#ZerkAlias` and the key merging they drive.
///
/// Merging is not a convenience. `Zerk<Storing>` and `Zerk<Persisting>` are the
/// same generic specialization, so registering an injectable under each emits
/// two `inject()` members on one type — `invalid redeclaration of 'inject()'`.
/// Zerk did exactly that before aliases were understood, so several of these
/// cases are regression tests for a generated file that would not compile.
@Suite("Zerk aliases")
struct ZerkAliasTests {

    // MARK: - Key merging

    @Test("an aliased parameter resolves from the underlying key's provider")
    func aliasedParameterResolves() {
        let source = """
        protocol Storing {}

        @ZerkAlias
        typealias Persisting = Storing

        @Injectable<Storing>
        final class FileStore: Storing {
            @InjectableProviding
            init() {}
        }

        @Injectable
        final class Consumer {
            @InjectableProviding
            init(store: Persisting) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        // Resolved, not bubbled up to the caller.
        #expect(result.output.output.contains("static func inject() -> Consumer"))
        #expect(!result.output.output.contains("inject(store:"))
    }

    @Test("the freestanding form merges keys just as the attached one does")
    func freestandingFormMergesKeys() {
        let source = """
        protocol Storing {}
        typealias Persisting = Storing

        #ZerkAlias<Storing, Persisting>()

        @Injectable<Storing>
        final class FileStore: Storing {
            @InjectableProviding
            init() {}
        }

        @Injectable
        final class Consumer {
            @InjectableProviding
            init(store: Persisting) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(!result.output.output.contains("inject(store:"))
    }

    @Test("only one extension is emitted for an aliased key")
    func oneExtensionPerAliasedKey() {
        // The regression: two extensions on one specialization, each declaring
        // inject(), is `invalid redeclaration of 'inject()'`.
        let source = """
        protocol Storing {}

        @ZerkAlias
        typealias Persisting = Storing

        @Injectable<Storing>(primary: true)
        final class FileStore: Storing {
            @InjectableProviding
            init() {}
        }

        @Injectable<Persisting>
        final class MemoryStore: Storing {
            @InjectableProviding
            init() {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        let extensionCount = CompileFixture.memberExtensionCount(in: result.output.output)
        #expect(extensionCount == 1)
        #expect(result.output.output.contains("extension Zerk<Storing> {"))
        // Both providers land in that one extension.
        #expect(result.output.output.contains("static var fileStore: Storing"))
        #expect(result.output.output.contains("static var memoryStore: Storing"))
    }

    @Test("alias equivalence is transitive")
    func aliasesAreTransitive() {
        let source = """
        protocol Storing {}

        @ZerkAlias
        typealias Persisting = Storing

        @ZerkAlias
        typealias Caching = Persisting

        @Injectable<Storing>
        final class FileStore: Storing {
            @InjectableProviding
            init() {}
        }

        @Injectable
        final class Consumer {
            @InjectableProviding
            init(store: Caching) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(!result.output.output.contains("inject(store:"))
    }

    // MARK: - Representative election

    @Test("the underlying type represents the group, not the alias")
    func underlyingTypeIsTheRepresentative() {
        let source = """
        @ZerkAlias
        typealias Names = [String]

        @InjectableValue
        var names: Names { ["a"] }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        // `Names` is the alias, so `Array<String>` wins.
        #expect(result.output.output.contains("extension Zerk<Array<String>> {"))
        #expect(!result.output.output.contains("extension Zerk<Names>"))
    }

    @Test("a peer group with no underlying falls back to alphabetical")
    func peerGroupElectsAlphabetically() {
        let source = """
        protocol Zebra {}
        typealias Apple = Zebra

        #ZerkAlias<Zebra, Apple>()

        @Injectable<Zebra>
        final class Impl: Zebra {
            @InjectableProviding
            init() {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.output.contains("extension Zerk<Apple> {"))
    }

    @Test("an any spelling survives the merge")
    func anySpellingSurvivesMerge() {
        let source = """
        protocol Storing {}

        @ZerkAlias
        typealias Persisting = Storing

        @Injectable<any Persisting>
        final class FileStore: Storing {
            @InjectableProviding
            init() {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.isEmpty)
        // Representative is `Storing`, but the author asked for an existential
        // spelling and every member of the group denotes the same type.
        #expect(result.output.output.contains("extension Zerk<any Storing> {"))
    }

    // MARK: - Diagnostics

    @Test("a collision caused by an alias explains the alias")
    func collisionNamesTheAlias() {
        let source = """
        protocol Storing {}

        @ZerkAlias
        typealias Persisting = Storing

        @Injectable<Storing>
        final class FileStore: Storing {
            @InjectableProviding
            init() {}
        }

        @Injectable<Persisting>
        final class MemoryStore: Storing {
            @InjectableProviding
            init() {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.diagnostics.contains {
            $0.severity == .error
                && $0.message.contains("Multiple types are injectable under 'Storing'")
                && $0.message.contains("'Storing' and 'Persisting' are the same type")
                && $0.message.contains("@ZerkAlias")
        })
    }

    @Test("an unmarked typealias merges nothing")
    func unmarkedTypealiasIsIgnored() {
        // Without the marker the plugin has no reason to believe the two names
        // are related, so the parameter stays caller-supplied.
        let source = """
        protocol Storing {}
        typealias Persisting = Storing

        @Injectable<Storing>
        final class FileStore: Storing {
            @InjectableProviding
            init() {}
        }

        @Injectable
        final class Consumer {
            @InjectableProviding
            init(store: Persisting) {}
        }
        """

        let result = CompileFixture.generateWithResolution(source: source)

        #expect(result.output.output.contains("inject(store: Persisting)"))
    }

    @Test("a generic typealias is not collected")
    func genericTypealiasIsIgnored() {
        // The macro reports it; the plugin must not act on it either, or it
        // would merge `Pair` with a spelling that means nothing without
        // substitution.
        let source = """
        @ZerkAlias
        typealias Pair<T> = (T, T)
        """

        let collector = aliasCollector(for: source)
        #expect(collector.aliasDeclarations.isEmpty)
    }

    // MARK: - KeyAliases

    @Test("union-find groups chained aliases under one representative")
    func unionFindGroupsChains() {
        let aliases = KeyAliases(declarations: [
            AliasDeclaration(keys: ["Persisting", "Storing"], aliasKey: "Persisting", location: aliasLocation()),
            AliasDeclaration(keys: ["Caching", "Persisting"], aliasKey: "Caching", location: aliasLocation()),
        ])

        #expect(aliases.representative(for: "Caching") == "Storing")
        #expect(aliases.representative(for: "Persisting") == "Storing")
        #expect(aliases.representative(for: "Storing") == "Storing")
        // Untouched keys pass through.
        #expect(aliases.representative(for: "Unrelated") == "Unrelated")
        #expect(aliases.aliases(of: "Storing").sorted() == ["Caching", "Persisting"])
    }

    @Test("an empty alias set changes nothing")
    func emptyAliasSetIsIdentity() {
        #expect(KeyAliases.empty.isEmpty)
        #expect(KeyAliases.empty.representative(for: "Storing") == "Storing")
    }

    // MARK: - The rewriting pass carries every field

    @Test("the rewriting pass carries every TypeRecord field it does not rewrite")
    func rewritingPassPreservesEveryField() {
        // Regression guard for the shape, not for one field. `AliasRewriter`
        // rebuilt each `ParameterRecord` field by field once and dropped
        // `isAutoInjected`; `rewrite(types:)` had the same shape, and the
        // memberwise initializer only *requires* the fields without defaults —
        // so a future `var x: T = default` on `TypeRecord` could be forgotten
        // and still compile.
        //
        // The aliases below are non-empty, so the pass runs rather than
        // short-circuiting, but relate keys this record never mentions. Nothing
        // is therefore eligible for rewriting and the output must equal the
        // input, field for field. Reflection rather than an explicit list: a
        // hand-written list of fields is the very thing that goes stale.
        let aliases = KeyAliases(declarations: [
            AliasDeclaration(keys: ["Persisting", "Storing"], aliasKey: "Persisting", location: aliasLocation())
        ])

        let original = populatedTypeRecord()
        let rewritten = AliasRewriter(aliases: aliases).rewrite(types: [original])

        try! #require(rewritten.count == 1)

        let before = fieldDescriptions(of: original)
        let after = fieldDescriptions(of: rewritten[0])

        #expect(before.keys.sorted() == after.keys.sorted())
        for (field, value) in before {
            #expect(after[field] == value, "'\(field)' did not survive the rewriting pass")
        }
    }
}

/// A `TypeRecord` with every field set to something distinguishable, keyed on
/// names no alias group in these tests touches.
///
/// Single-entry dictionaries and single-element arrays keep `String(describing:)`
/// deterministic — a multi-entry dictionary's description order is not stable
/// across runs, which would make the comparison flaky rather than strict.
private func populatedTypeRecord() -> TypeRecord {
    let location = aliasLocation()
    let parameter = ParameterRecord(
        label: "with",
        name: "seed",
        typeKey: "Int",
        typeName: "Int",
        isAutoInjected: true,
        feedsDependencies: true,
        location: location
    )
    let provider = InjectingProvider(
        kind: .staticFunction(name: "live"),
        parameters: [parameter],
        effects: .none,
        location: location,
        returnTypeName: "Unrelated",
        isolation: .globalActor("MainActor"),
        isPrimary: true
    )

    return TypeRecord(
        name: "Unrelated",
        injectableKeys: ["Unrelated": location],
        exportedKeys: ["Unrelated": location],
        primaryKeys: ["Unrelated": location],
        defaultProviders: [provider],
        typedProviders: ["Unrelated": [provider]],
        initializers: [InitializerRecord(
            parameters: [parameter],
            effects: .none,
            location: location,
            isolation: .globalActor("MainActor")
        )],
        isSingleton: true,
        isolation: .globalActor("MainActor")
    )
}

/// Every stored property of a record, by label, rendered as text.
///
/// Comparing descriptions avoids conforming the whole model graph to
/// `Equatable` for one test, and a field added later is picked up with no change
/// here — which is the point.
private func fieldDescriptions(of record: TypeRecord) -> [String: String] {
    var fields: [String: String] = [:]
    for child in Mirror(reflecting: record).children {
        guard let label = child.label else { continue }
        fields[label] = String(describing: child.value)
    }
    return fields
}

private func aliasLocation() -> AttributeLocation {
    AttributeLocation(filePath: "/tmp/Alias.swift", line: 1, column: 1)
}

/// A collector walked over one source, for assertions about what it *recorded*
/// rather than what the generator did with it.
private func aliasCollector(for source: String) -> SourceCollector {
    let collector = SourceCollector()
    collector.walk(Parser.parse(source: source))
    return collector
}
