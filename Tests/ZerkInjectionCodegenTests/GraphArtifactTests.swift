//
//  GraphArtifactTests.swift
//  Zerk
//

import Foundation
import Testing
@testable import CodegenToolkit

/// The `Zerk.graph.json` artifact.
///
/// What is being protected is a claim rather than a format: the graph says what
/// the generated code *does*. Every test here therefore asserts against a
/// decision the emitter also makes — which provider is primary, what a parameter
/// resolves to, how long an instance lives — so a change that moved one without
/// the other would fail here.
@Suite("Graph artifact")
struct GraphArtifactTests {

    private static let source = """
    protocol Caching: AnyObject {}
    protocol Reporting {}

    extension InjectionScope {
        nonisolated static let session = InjectionScope("session")
    }

    @InjectableValue
    var baseURL: String { "https://example.com" }

    @Scoped(.session)
    @Injectable<Caching>
    final class SessionCache: Caching {
        @InjectableProviding
        init(baseURL: String) {}
    }

    @Singleton
    @Injectable(public: true)
    final class Clock {
        @InjectableProviding
        init() {}
    }

    @Injectable<Reporting>(primary: true)
    struct LiveReporter: Reporting {
        @InjectableProviding<Reporting>(primary: true)
        static func live(cache: Caching) -> Reporting { LiveReporter() }

        @InjectableProviding<Reporting>
        static func offline(label: String) -> Reporting { LiveReporter() }
    }
    """

    private func key(_ name: String, in graph: ZerkGraph) -> ZerkGraph.Key? {
        graph.keys.first { $0.key == name }
    }

    // MARK: - Shape

    @Test("every key and value in the module appears")
    func coversTheModule() {
        let graph = CompileFixture.graph(source: Self.source)

        #expect(graph.formatVersion == ZerkGraph.currentFormatVersion)
        #expect(Set(graph.keys.map(\.key)) == ["Caching", "Clock", "Reporting"])
        #expect(graph.values.map(\.name) == ["baseURL"])
        #expect(graph.values.first?.key == "String")
    }

    @Test("lifetimes are recorded, with the scope named")
    func recordsLifetimes() {
        let graph = CompileFixture.graph(source: Self.source)

        let cache = key("Caching", in: graph)?.providers.first
        #expect(cache?.lifetime == "scoped")
        #expect(cache?.scope == "session")

        let clock = key("Clock", in: graph)?.providers.first
        #expect(clock?.lifetime == "singleton")
        #expect(clock?.scope == nil)

        let reporter = key("Reporting", in: graph)?.providers.first
        #expect(reporter?.lifetime == "transient")
    }

    @Test("the primary provider is identified, and only it")
    func identifiesThePrimary() {
        let graph = CompileFixture.graph(source: Self.source)
        let reporting = key("Reporting", in: graph)

        // Two providers for the key; exactly one backs `inject()`.
        #expect(reporting?.providers.count == 2)
        #expect(reporting?.primaryMember == "live")
        #expect(reporting?.providers.filter(\.isPrimary).map(\.memberName) == ["live"])
    }

    @Test("member names match what the generator emits")
    func memberNamesAgreeWithTheGeneratedCode() {
        let graph = CompileFixture.graph(source: Self.source)
        let generated = CompileFixture.generate(source: Self.source)

        // The artifact's whole value is describing the code, so a name it
        // reports must be a name that exists.
        for graphKey in graph.keys {
            for provider in graphKey.providers {
                #expect(
                    generated.contains("static var \(provider.memberName)")
                        || generated.contains("static func \(provider.memberName)"),
                    "graph names '\(provider.memberName)', generated code has no such member"
                )
            }
        }
    }

    @Test("export is recorded per key")
    func recordsExport() {
        let graph = CompileFixture.graph(source: Self.source)

        #expect(key("Clock", in: graph)?.isExported == true)
        #expect(key("Caching", in: graph)?.isExported == false)
    }

    // MARK: - Edges

    @Test("a dependency on another injectable names the key it resolves to")
    func recordsInjectableEdges() {
        let graph = CompileFixture.graph(source: Self.source)
        let live = key("Reporting", in: graph)?.providers.first { $0.memberName == "live" }
        let dependency = live?.dependencies.first

        #expect(live?.dependencies.count == 1)
        #expect(dependency?.source == "injectable")
        #expect(dependency?.key == "Caching")
        #expect(dependency?.parameterName == "cache")
    }

    @Test("a dependency satisfied by a value names the value, not just its key")
    func recordsValueEdges() {
        let graph = CompileFixture.graph(source: Self.source)
        let dependency = key("Caching", in: graph)?.providers.first?.dependencies.first

        // Values are matched by name *and* key, so the key alone would not
        // identify which one was chosen.
        #expect(dependency?.source == "value")
        #expect(dependency?.key == "String")
        #expect(dependency?.valueName == "baseURL")
    }

    @Test("a parameter nothing resolves is recorded as the caller's")
    func recordsCallerSuppliedParameters() {
        let graph = CompileFixture.graph(source: Self.source)
        let offline = key("Reporting", in: graph)?.providers.first { $0.memberName == "offline" }
        let dependency = offline?.dependencies.first

        // `label: String` has no matching value, so it bubbles up as a
        // parameter of the generated member. That is the graph's boundary, not
        // a gap in it.
        #expect(dependency?.source == "caller")
        #expect(dependency?.key == nil)
        #expect(dependency?.parameterName == "label")
    }

    // MARK: - Other registration shapes

    @Test("a generic key is marked as one")
    func marksGenericKeys() {
        let graph = CompileFixture.graph(source: """
        @Injectable
        struct Cache<E> {
            @InjectableProviding
            init() {}
        }
        """)

        #expect(graph.keys.count == 1)
        #expect(graph.keys.first?.isGeneric == true)
    }

    @Test("an imported key appears, marked, with no providers")
    func includesImportedKeys() {
        let graph = CompileFixture.graph(source: """
        protocol Remote {}

        enum Imports {
            @ImportedInjectable
            static func remote() -> Remote { Zerk<Remote>.inject() }
        }
        """)

        let remote = graph.keys.first { $0.key == "Remote" }
        // Reachable as an edge target, so it has to be findable — and honest
        // about the fact that nothing here builds it.
        #expect(remote?.isImported == true)
        #expect(remote?.providers.isEmpty == true)
        #expect(remote?.primaryMember == nil)
    }

    @Test("isolation and effects are recorded")
    func recordsIsolationAndEffects() {
        let graph = CompileFixture.graph(source: """
        protocol Serving {}

        @MainActor
        @Injectable<Serving>
        struct Live: Serving {
            @InjectableProviding<Serving>
            static func make() async throws -> Serving { Live() }
        }
        """)

        let provider = graph.keys.first?.providers.first
        #expect(provider?.isolation == "MainActor")
        #expect(provider?.isAsync == true)
        #expect(provider?.isThrowing == true)
    }

    /// Effects are a claim about the *emitted member*, so they are checked
    /// against it rather than against the source.
    ///
    /// A kept instance is where the two part company: `@Singleton` with an
    /// `init() throws` is emitted `async throws`, because joining the box's one
    /// build is what suspends — and the graph reported `throws` alone. That is
    /// the wrong answer to the question a consumer brings to these two fields,
    /// which is whether a call site needs `await`.
    ///
    /// Written over the effect axis rather than for the one reported case: the
    /// same rule has four readers, and this is the graph's.
    @Test("effects match the emitted inject()", arguments: ["", "throws", "async", "async throws"])
    func effectsAgreeWithTheGeneratedCode(effect: String) {
        let source = """
        protocol Connecting {}

        @Singleton
        @Injectable<Connecting>
        final class Client: Connecting, @unchecked Sendable {
            init() \(effect) {}
        }

        @Injectable
        struct Consumer {
            let connecting: Connecting
        }
        """

        let graph = CompileFixture.graph(source: source)
        let generated = CompileFixture.generate(source: source)

        for graphKey in graph.keys {
            guard let primary = graphKey.providers.first(where: \.isPrimary) else {
                continue
            }
            let effects = ProviderEffects(isAsync: primary.isAsync,
                                          isThrowing: primary.isThrowing)
            #expect(generated.contains(
                "static func inject()\(effects.declarationSuffix) -> \(graphKey.displayName) {"),
                    "\(graphKey.key) reports '\(effects.declarationSuffix)':\n\(generated)")
        }
    }

    // MARK: - The file itself

    @Test("encoding is deterministic")
    func encodingIsDeterministic() throws {
        // A build output that changed every build would invalidate downstream
        // work and dirty every diff that touched it.
        let first = try CompileFixture.graph(source: Self.source).encoded()
        let second = try CompileFixture.graph(source: Self.source).encoded()
        #expect(first == second)
    }

    @Test("the artifact round-trips")
    func roundTrips() throws {
        let graph = CompileFixture.graph(source: Self.source)
        let decoded = try JSONDecoder().decode(ZerkGraph.self, from: graph.encoded())
        #expect(decoded == graph)
    }

    @Test("optional fields are omitted rather than written as null")
    func omitsAbsentOptionals() throws {
        let graph = CompileFixture.graph(source: Self.source)
        let object = try JSONSerialization.jsonObject(
            with: graph.encoded()) as? [String: Any]
        let keys = object?["keys"] as? [[String: Any]] ?? []
        let clock = keys.first { $0["key"] as? String == "Clock" }
        let provider = (clock?["providers"] as? [[String: Any]])?.first

        // Documented on `ZerkGraph`, and asserted here so it stays true: a
        // consumer that subscripts rather than asks would break silently.
        #expect(provider?["scope"] == nil)
        #expect(provider?["lifetime"] as? String == "singleton")
    }

    @Test("no graph is written unless one is asked for")
    func graphIsOptOut() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("zerk-graph-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("Input.swift")
        try "@Injectable struct Thing { @InjectableProviding init() {} }"
            .write(to: input, atomically: true, encoding: .utf8)
        let output = directory.appendingPathComponent("Zerk.generated.swift")

        // Invoked without `--graph`, the tool keeps its old contract of writing
        // exactly one file.
        try CodeGenerator(inputPaths: [input.path], outputPath: output.path).run()
        #expect(FileManager.default.fileExists(atPath: output.path))
        #expect(!FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("Zerk.graph.json").path))

        // And writes it where asked when asked.
        let graph = directory.appendingPathComponent("Zerk.graph.json")
        try CodeGenerator(inputPaths: [input.path],
                          outputPath: output.path,
                          graphPath: graph.path).run()
        #expect(FileManager.default.fileExists(atPath: graph.path))
        let decoded = try JSONDecoder().decode(ZerkGraph.self, from: Data(contentsOf: graph))
        #expect(decoded.keys.map(\.key) == ["Thing"])
    }
}

/// The format version, and what it is for.
@Suite("Graph format version")
struct GraphFormatVersionTests {

    private static func export(_ json: String) throws -> Result<String, GraphExport.Failure> {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("zerk-version-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("Zerk.graph.json")
        try Data(json.utf8).write(to: url)

        do {
            return .success(try GraphExport(inputPaths: [url.path], format: "json").run() ?? "")
        } catch let failure as GraphExport.Failure {
            return .failure(failure)
        }
    }

    /// A version nobody reads is decoration. `Codable` ignores unknown fields
    /// and defaults missing ones, so a graph of *any* other version decodes
    /// "fine" and the caller silently reads one whose meaning has changed — the
    /// situation the version exists to make detectable.
    ///
    /// Both directions, because only one of them used to be checked. The guard
    /// was "no newer than", and an older graph is not a subset of a newer one:
    /// version 3 repurposed `isAsync`/`isThrowing` from what building a provider
    /// costs to what reading it costs, so a version 2 document says
    /// `isAsync: false` where 3 says `true` — and the merged output is stamped
    /// with the current version either way, leaving nothing able to tell.
    @Test("only the current format version is read", arguments: [
        ZerkGraph.currentFormatVersion,
        ZerkGraph.currentFormatVersion + 1,
        ZerkGraph.currentFormatVersion - 1,
        ZerkGraph.currentFormatVersion - 2,
    ])
    func onlyTheCurrentVersionIsRead(version: Int) throws {
        let result = try Self.export("""
        {"formatVersion": \(version), "keys": [], "values": []}
        """)

        guard version != ZerkGraph.currentFormatVersion else {
            guard case .success = result else {
                Issue.record("the current format was refused: \(result)")
                return
            }
            return
        }

        guard case .failure(let failure) = result else {
            Issue.record("version \(version) was accepted: \(result)")
            return
        }
        // Both versions named: "wrong version" without saying which is a
        // message the reader has to go and look something up to act on.
        #expect(failure.message.contains("format version \(version)"))
        #expect(failure.message.contains("reads version \(ZerkGraph.currentFormatVersion)"))
    }
}
