import Testing
import SwiftParser
@testable import CodegenToolkit

@Suite("ProviderResolver")
struct ProviderResolverTests {
    @Test("a typed provider joins the default provider rather than replacing it")
    func typedProviderJoinsDefaultProvider() {
        let record = makeTypeRecord(
            name: "APIService",
            injectableKeys: ["Service", "APIService"],
            defaultProviders: [makeInitializerProvider(isPrimary: true)],
            typedProviders: ["Service": [makeStaticProvider(name: "live", location: makeLocation(line: 20))]]
        )

        let result = ProviderResolver(types: [record]).resolve()

        #expect(result.diagnostics.isEmpty)
        // 'Service' is served by both the untyped initializer and the typed
        // factory; 'APIService' only by the initializer.
        #expect(result.resolutions.count == 3)
        #expect(result.resolutions.contains { $0.injectableKey == "Service" && $0.provider.memberNameHint == "live" })
        #expect(result.resolutions.contains { $0.injectableKey == "Service" && $0.provider.memberNameHint == nil })
        #expect(result.resolutions.contains { $0.injectableKey == "APIService" && $0.provider.memberNameHint == nil })
        #expect(result.primaryResolutions["Service"]?.provider.memberNameHint == nil)
        #expect(result.primaryResolutions["APIService"]?.provider.memberNameHint == nil)
    }

    @Test("several typed providers for one key all resolve")
    func severalTypedProvidersAllResolve() {
        let record = makeTypeRecord(
            name: "Loader",
            injectableKeys: ["Loading"],
            typedProviders: [
                "Loading": [
                    makeStaticProvider(name: "live", isPrimary: true),
                    makeStaticProvider(name: "cached", location: makeLocation(line: 20))
                ]
            ]
        )

        let result = ProviderResolver(types: [record]).resolve()

        #expect(result.diagnostics.isEmpty)
        #expect(result.resolutions.count == 2)
        #expect(result.primaryResolutions["Loading"]?.provider.memberNameHint == "live")
    }

    @Test("a singleton may not declare more than one provider for a key")
    func singletonRejectsMultipleProviders() {
        let record = makeTypeRecord(
            name: "Loader",
            injectableKeys: ["Loading"],
            typedProviders: [
                "Loading": [
                    makeStaticProvider(name: "live", isPrimary: true),
                    makeStaticProvider(name: "cached", location: makeLocation(line: 20))
                ]
            ],
            isSingleton: true
        )

        let result = ProviderResolver(types: [record]).resolve()

        #expect(result.resolutions.isEmpty)
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].message.contains("@Singleton 'Loader' declares multiple providers for 'Loading'"))
    }

    @Test("missing provider emits error when implicit initializer cannot be inferred")
    func missingProviderEmitsError() {
        let record = makeTypeRecord(
            name: "Client",
            injectableKeys: ["Client"],
            initializers: [
                makeInitializerRecord(),
                makeInitializerRecord(parameters: [makeParameter(label: "id", name: "id", typeKey: "Int")])
            ]
        )

        let result = ProviderResolver(types: [record]).resolve()

        #expect(result.resolutions.isEmpty)
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].message.contains("No @InjectableProviding provider found"))
    }

    @Test("multiple primary types for a key emit diagnostics")
    func multiplePrimariesEmitDiagnostics() {
        let first = makeTypeRecord(
            name: "LiveService",
            injectableKeys: ["Service"],
            primaryKeys: ["Service"],
            defaultProviders: [makeInitializerProvider(location: makeLocation(line: 10))]
        )
        let second = makeTypeRecord(
            name: "BackupService",
            injectableKeys: ["Service"],
            primaryKeys: ["Service"],
            defaultProviders: [makeInitializerProvider(location: makeLocation(line: 20))]
        )

        let result = ProviderResolver(types: [first, second]).resolve()

        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].message.contains("Multiple primary injectables found for 'Service'"))
        #expect(result.primaryResolutions["Service"] == nil)
    }

    @Test("selective shared keys are tracked per injectable key")
    func selectiveSharedKeysAreTrackedPerInjectableKey() {
        let record = makeTypeRecord(
            name: "LiveService",
            injectableKeys: ["Service", "LiveService"],
            sharedKeys: ["Service"],
            defaultProviders: [makeInitializerProvider()]
        )

        let result = ProviderResolver(types: [record]).resolve()

        #expect(result.diagnostics.isEmpty)
        #expect(result.resolutions.contains { $0.injectableKey == "Service" && $0.isShared })
        #expect(result.resolutions.contains { $0.injectableKey == "LiveService" && !$0.isShared })
    }

    @Test("injectable type with synthesized empty initializer is inferred as a provider")
    func synthesizedEmptyInitializerIsInferred() {
        let source = """
        @Injectable<FirebaseAIManaging>
        public class FirebaseAIManager: FirebaseAIManaging {
            private let ai = 1
        }
        """

        let collector = SourceCollector()
        collector.walk(Parser.parse(source: source))

        #expect(collector.diagnostics.isEmpty)
        #expect(collector.types.count == 1)
        #expect(collector.types[0].initializers.count == 1)
        #expect(collector.types[0].initializers[0].parameters.isEmpty)

        let result = ProviderResolver(types: collector.types).resolve()

        #expect(result.diagnostics.isEmpty)
        #expect(result.resolutions.count == 1)
        #expect(result.resolutions[0].injectableKey == "FirebaseAIManaging")
    }

    @Test("injectable struct with synthesized memberwise initializer is inferred as a provider")
    func synthesizedStructMemberwiseInitializerIsInferred() {
        let source = """
        @Injectable<Service>
        struct LiveService: Service {
            let client: APIClient
            let logger: Logger = DefaultLogger()
        }
        """

        let collector = SourceCollector()
        collector.walk(Parser.parse(source: source))

        #expect(collector.diagnostics.isEmpty)
        #expect(collector.types.count == 1)
        #expect(collector.types[0].initializers.count == 1)
        #expect(collector.types[0].initializers[0].parameters.count == 1)
        #expect(collector.types[0].initializers[0].parameters[0].name == "client")
        #expect(collector.types[0].initializers[0].parameters[0].typeKey == "APIClient")

        let result = ProviderResolver(types: collector.types).resolve()

        #expect(result.diagnostics.isEmpty)
        #expect(result.resolutions.count == 1)
        #expect(result.resolutions[0].injectableKey == "Service")
    }

    @Test("injectable type is collected when mixed with unrelated type annotations")
    func injectableTypeWithOtherAnnotationsIsCollected() {
        let source = """
        @MainActor
        @Observable
        @Injectable<Service>
        final class LiveService: Service {
            private let client = APIClient()
        }
        """

        let collector = SourceCollector()
        collector.walk(Parser.parse(source: source))

        #expect(collector.diagnostics.isEmpty)
        #expect(collector.types.count == 1)
        #expect(collector.types[0].injectableKeys.keys.contains("Service"))
        #expect(collector.types[0].isolation == .globalActor("MainActor"))

        let result = ProviderResolver(types: collector.types).resolve()

        // Isolated providers are supported: the isolation is carried through
        // to the generated member rather than rejected.
        #expect(result.diagnostics.isEmpty)
        #expect(result.resolutions.count == 1)
        #expect(result.resolutions[0].injectableKey == "Service")
        #expect(result.resolutions[0].isolation == .globalActor("MainActor"))

        let output = buildOutput(
            types: collector.types,
            values: collector.values,
            resolutions: result.resolutions
        )

        #expect(output.diagnostics.isEmpty)
        #expect(output.output.contains("@MainActor static var liveService: Service {"))
        #expect(output.output.contains("@MainActor static func inject() -> Service {"))
        #expect(output.output.contains("@MainActor static var interjectedLiveService: Service? { get }"))
    }

    @Test("@Singleton on a value type emits a diagnostic")
    func singletonOnValueTypeEmitsDiagnostic() {
        let source = """
        @Singleton
        @Injectable
        struct Config {
            init() {}
        }
        """

        let collector = SourceCollector()
        collector.walk(Parser.parse(source: source))

        #expect(collector.diagnostics.count == 1)
        #expect(collector.diagnostics[0].message.contains("reference types"))
    }

    @Test("@Isolated<A> overrides the actor-name heuristic")
    func isolatedMarkerOverridesHeuristic() {
        let source = """
        @Isolated<DataStore>
        @DataStore
        @Injectable<Storing>
        final class FileStore: Storing {
            init() {}
        }
        """

        let collector = SourceCollector()
        collector.walk(Parser.parse(source: source))

        #expect(collector.diagnostics.isEmpty)
        #expect(collector.types.count == 1)
        // "DataStore" does not end in "Actor", so only the marker can see it.
        #expect(collector.types[0].isolation == .globalActor("DataStore"))
    }

    @Test("@Isolated<A> contradicting nonisolated emits a diagnostic")
    func isolatedMarkerContradictingNonisolatedEmitsDiagnostic() {
        let source = """
        @Isolated<MainActor>
        @Injectable<Storing>
        nonisolated final class FileStore: Storing {
            init() {}
        }
        """

        let collector = SourceCollector()
        collector.walk(Parser.parse(source: source))

        #expect(collector.diagnostics.count == 1)
        #expect(collector.diagnostics[0].message.contains("contradicts the 'nonisolated' modifier"))
    }

    @Test("@Isolated<A> on an actor emits a diagnostic")
    func isolatedMarkerOnActorEmitsDiagnostic() {
        let source = """
        @Isolated<MainActor>
        @Injectable<Storing>
        actor FileStore: Storing {
            init() {}
        }
        """

        let collector = SourceCollector()
        collector.walk(Parser.parse(source: source))

        #expect(collector.diagnostics.count == 1)
        #expect(collector.diagnostics[0].message.contains("construction is nonisolated"))
    }

    @Test("ambient MainActor default is applied to unannotated declarations")
    func ambientDefaultIsApplied() {
        let source = """
        @Injectable<Service>
        final class LiveService: Service {
            init() {}
        }

        @Injectable
        var baseURL: String { "https://example.com" }
        """

        let collector = SourceCollector(
            settings: ZerkSettings(
                defaultActorIsolation: .globalActor("MainActor"),
                swiftVersion: "6",
                sourcePath: nil
            )
        )
        collector.walk(Parser.parse(source: source))

        #expect(collector.diagnostics.isEmpty)
        #expect(collector.types[0].isolation == .globalActor("MainActor"))
        #expect(collector.types[0].initializers[0].isolation == .globalActor("MainActor"))
        #expect(collector.values[0].isolation == .globalActor("MainActor"))
    }

    @Test("an actor stays nonisolated under an ambient MainActor default")
    func actorStaysNonisolatedUnderAmbientDefault() {
        let source = """
        @Injectable<Storing>
        actor FileStore: Storing {
            init() {}
        }
        """

        let collector = SourceCollector(
            settings: ZerkSettings(
                defaultActorIsolation: .globalActor("MainActor"),
                swiftVersion: "6",
                sourcePath: nil
            )
        )
        collector.walk(Parser.parse(source: source))

        #expect(collector.diagnostics.isEmpty)
        #expect(collector.types[0].isolation == .nonisolated)
        #expect(collector.types[0].initializers[0].isolation == .nonisolated)
    }

    @Test("nonisolated providers on main-actor types drop the type isolation")
    func nonisolatedProviderDropsTypeIsolation() {
        let source = """
        @MainActor
        @Injectable<Service>
        final class LiveService: Service {
            @InjectableProviding
            nonisolated static func live() -> Service {
                LiveService()
            }

            init() {}
        }
        """

        let collector = SourceCollector()
        collector.walk(Parser.parse(source: source))

        #expect(collector.diagnostics.isEmpty)
        #expect(collector.types.count == 1)
        #expect(collector.types[0].isolation == .globalActor("MainActor"))
        #expect(collector.types[0].defaultProviders.count == 1)
        #expect(collector.types[0].defaultProviders[0].isolation == .nonisolated)
        #expect(collector.types[0].initializers.count == 1)
        #expect(collector.types[0].initializers[0].isolation == .globalActor("MainActor"))
    }

    @Test("injectable value is collected when mixed with property wrappers")
    func injectableValueWithPropertyWrappersIsCollected() {
        let source = """
        final class SettingsStore {
            @Published
            @Injectable<String>
            var apiKey: String = "secret"
        }
        """

        let collector = SourceCollector()
        collector.walk(Parser.parse(source: source))

        #expect(collector.diagnostics.isEmpty)
        #expect(collector.values.count == 1)
        #expect(collector.values[0].name == "apiKey")
        #expect(collector.values[0].typeKey == "String")
        #expect(collector.values[0].bodyText == #""secret""#)
    }

    @Test("injectable struct with bindable wrapped property keeps synthesized memberwise parameter")
    func injectableStructWithBindablePropertyKeepsSynthesizedMemberwiseParameter() {
        let source = """
        @Injectable<ViewModelHosting>
        struct HostingViewModel: ViewModelHosting {
            @Bindable var model: SearchModel
            let logger: Logger = DefaultLogger()
        }
        """

        let collector = SourceCollector()
        collector.walk(Parser.parse(source: source))

        #expect(collector.diagnostics.isEmpty)
        #expect(collector.types.count == 1)
        #expect(collector.types[0].initializers.count == 1)
        #expect(collector.types[0].initializers[0].parameters.count == 1)
        #expect(collector.types[0].initializers[0].parameters[0].name == "model")
        #expect(collector.types[0].initializers[0].parameters[0].typeKey == "SearchModel")
    }
}

@Suite("GeneratorOutputBuilder")
struct GeneratorOutputBuilderTests {
    @Test("injectable values generate Zerk typed extensions")
    func valuesGenerateTypedExtensions() {
        let value = InjectableValueRecord(
            name: "baseURL",
            typeKey: "String",
            typeName: "String",
            bodyText: "\"https://api.example.com\"",
            location: makeLocation()
        )

        let result = buildOutput(types: [], values: [value], resolutions: [])

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.contains("extension Zerk<String> {"))
        #expect(result.output.contains("static var baseURL: String"))
    }

    @Test("a singleton stores one instance in _$zerk_singletons and reads it through a getter")
    func singletonStoresInSharedNamespace() {
        let serviceProvider = makeInitializerProvider(
            parameters: [makeParameter(label: "baseURL", name: "baseURL", typeKey: "String", typeName: "String")]
        )
        let resolution = makeResolution(
            typeName: "ApiService",
            injectableKey: "ApiServicing",
            provider: .explicit(serviceProvider),
            isSingleton: true
        )
        let value = InjectableValueRecord(
            name: "baseURL",
            typeKey: "String",
            typeName: "String",
            bodyText: "\"https://api.example.com\"",
            location: makeLocation()
        )

        let result = buildOutput(types: [], values: [value], resolutions: [resolution])

        #expect(result.diagnostics.isEmpty)
        // Storage is typed as the concrete type, not the key: one instance has
        // to be assignable to every key the type claims.
        #expect(result.output.contains("private enum _$zerk_singletons {"))
        #expect(result.output.contains("nonisolated(unsafe) static let apiService: ApiService = ApiService(baseURL: Zerk<String>.baseURL)"))
        #expect(result.output.contains("nonisolated static var apiService: ApiServicing {"))
        #expect(result.output.contains("return _$zerk_singletons.apiService"))
        #expect(result.output.contains("static func inject() -> ApiServicing"))
    }

    @Test("async or throwing singleton providers emit a diagnostic")
    func effectfulSingletonProvidersEmitDiagnostic() {
        let resolution = makeResolution(
            typeName: "ApiService",
            injectableKey: "ApiServicing",
            provider: .explicit(
                makeInitializerProvider(effects: ProviderEffects(isAsync: true, isThrowing: false))
            ),
            isSingleton: true
        )

        let result = buildOutput(types: [], values: [], resolutions: [resolution])

        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].message.contains("@Singleton providers cannot be async or throwing"))
    }

    @Test("isolated providers resolve without a diagnostic")
    func isolatedProvidersResolveCleanly() {
        let record = makeTypeRecord(
            name: "LiveService",
            injectableKeys: ["Service"],
            defaultProviders: [makeInitializerProvider(isolation: .globalActor("MainActor"))]
        )

        let result = ProviderResolver(types: [record]).resolve()

        #expect(result.diagnostics.isEmpty)
        #expect(result.resolutions.count == 1)
        #expect(result.resolutions[0].isolation == .globalActor("MainActor"))
    }

    @Test("a singleton whose dependency lives in another domain emits a diagnostic")
    func crossDomainSingletonDependencyEmitsDiagnostic() {
        let store = makeResolution(
            typeName: "Store",
            injectableKey: "Store",
            provider: .explicit(makeInitializerProvider(isolation: .globalActor("DataStore")))
        )
        let cache = makeResolution(
            typeName: "Cache",
            injectableKey: "Cache",
            provider: .explicit(
                makeInitializerProvider(
                    parameters: [makeParameter(label: "store", name: "store", typeKey: "Store")],
                    isolation: .globalActor("MainActor")
                )
            ),
            isSingleton: true
        )

        let result = buildOutput(types: [], values: [], resolutions: [store, cache])

        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].message.contains("crosses an isolation boundary"))
    }

    @Test("a nonisolated dependency reaches an isolated singleton for free")
    func nonisolatedDependencyReachesIsolatedSingleton() {
        let store = makeResolution(
            typeName: "Store",
            injectableKey: "Store",
            provider: .explicit(makeInitializerProvider())
        )
        let cache = makeResolution(
            typeName: "Cache",
            injectableKey: "Cache",
            provider: .explicit(
                makeInitializerProvider(
                    parameters: [makeParameter(label: "store", name: "store", typeKey: "Store")],
                    isolation: .globalActor("MainActor")
                )
            ),
            isSingleton: true
        )

        let result = buildOutput(types: [], values: [], resolutions: [store, cache])

        #expect(result.diagnostics.isEmpty)
        // Global-actor isolation already protects the storage, so it carries the
        // attribute rather than `nonisolated(unsafe)`.
        #expect(result.output.contains("@MainActor static let cache: Cache = Cache(store: Zerk<Store>.inject())"))
        #expect(result.output.contains("return _$zerk_singletons.cache"))
    }

    @Test("a singleton crossing into another domain emits a sendability check")
    func crossDomainSingletonEmitsSendabilityCheck() {
        let logger = makeResolution(
            typeName: "Logger",
            injectableKey: "Logger",
            provider: .explicit(makeInitializerProvider(isolation: .globalActor("MainActor"))),
            isSingleton: true
        )
        let reporter = makeResolution(
            typeName: "Reporter",
            injectableKey: "Reporter",
            provider: .explicit(
                makeInitializerProvider(
                    parameters: [makeParameter(label: "logger", name: "logger", typeKey: "Logger")]
                )
            )
        )

        let result = buildOutput(types: [], values: [], resolutions: [logger, reporter])

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.contains("private func _$zerk_sendable_conformance_check<T: Sendable>(_: T.Type) {}"))
        #expect(result.output.contains("_$zerk_sendable_conformance_check(Logger.self)"))
        // Reaching a MainActor singleton from a nonisolated member needs await,
        // so the member splits and the resolving variant is async.
        #expect(result.output.contains("nonisolated static func reporter(logger: Logger) -> Reporter {"))
        #expect(result.output.contains("nonisolated static func reporter() async -> Reporter {"))
        #expect(result.output.contains("reporter(logger: await Zerk<Logger>.inject())"))
    }

    @Test("an async dependency of a sync provider splits the member")
    func asyncDependencyOfSyncProviderSplitsMember() {
        let manager = makeResolution(
            typeName: "ApiManager",
            injectableKey: "ApiManager",
            provider: .explicit(
                makeInitializerProvider(effects: ProviderEffects(isAsync: true, isThrowing: false))
            )
        )
        let repository = makeResolution(
            typeName: "UserRepository",
            injectableKey: "UserRepository",
            provider: .explicit(
                makeInitializerProvider(
                    parameters: [makeParameter(label: "manager", name: "manager", typeKey: "ApiManager")]
                )
            )
        )

        let result = buildOutput(types: [], values: [], resolutions: [manager, repository])

        #expect(result.diagnostics.isEmpty)
        // The dependency cannot be a default argument — `await` is not allowed
        // there — so it becomes a required parameter on the explicit variant
        // and is resolved in the body of the resolving variant.
        #expect(result.output.contains("nonisolated static func userRepository(manager: ApiManager) -> UserRepository {"))
        #expect(result.output.contains("nonisolated static func userRepository() async -> UserRepository {"))
        #expect(result.output.contains("userRepository(manager: await Zerk<ApiManager>.inject())"))
        #expect(result.output.contains("= Zerk<ApiManager>.inject()") == false)
        // Exactly one construction point and one interjection guard.
        #expect(result.output.contains("return UserRepository(manager: manager)"))
        #expect(result.output.contains("nonisolated static func interjectedUserRepository(manager: ApiManager) -> UserRepository?"))
    }

    @Test("member name collisions within an injectable key emit a diagnostic")
    func memberNameCollisionsEmitDiagnostic() {
        let first = makeResolution(
            typeName: "LiveLoader",
            injectableKey: "Loading",
            provider: .explicit(makeStaticProvider(name: "live"))
        )
        let second = makeResolution(
            typeName: "BackupLoader",
            injectableKey: "Loading",
            provider: .explicit(makeStaticProvider(name: "live"))
        )

        let result = buildOutput(types: [], values: [], resolutions: [first, second])

        #expect(result.diagnostics.contains { $0.message.contains("collides") })
    }

    @Test("circular dependencies emit a diagnostic instead of degrading silently")
    func circularDependenciesEmitDiagnostic() {
        let a = makeResolution(
            typeName: "ServiceA",
            injectableKey: "A",
            provider: .explicit(makeInitializerProvider(
                parameters: [makeParameter(label: "b", name: "b", typeKey: "B", typeName: "B")]
            ))
        )
        let b = makeResolution(
            typeName: "ServiceB",
            injectableKey: "B",
            provider: .explicit(makeInitializerProvider(
                parameters: [makeParameter(label: "a", name: "a", typeKey: "A", typeName: "A")]
            ))
        )

        let result = buildOutput(types: [], values: [], resolutions: [a, b])

        #expect(result.diagnostics.contains { $0.message.contains("Circular dependency detected") })
    }

    @Test("@Shared on a non-public key clamps access and warns")
    func sharedOnInternalKeyClampsAccess() {
        let service = makeResolution(
            typeName: "LiveService",
            injectableKey: "Service",
            provider: .explicit(makeStaticProvider(name: "live")),
            isShared: true
        )

        let result = buildOutput(
            types: [],
            values: [],
            resolutions: [service],
            moduleAccessLevels: ["Service": false]
        )

        #expect(result.diagnostics.contains { $0.severity == .warning && $0.message.contains("@Shared has no effect") })
        #expect(result.output.contains("public ") == false)
        #expect(result.output.contains("nonisolated static func inject() -> Service"))
    }

    @Test("@Injected on an async or throwing chain emits a diagnostic")
    func injectedOnAsyncChainEmitsDiagnostic() {
        let repository = makeResolution(
            typeName: "UserRepository",
            injectableKey: "UserRepository",
            provider: .explicit(
                makeInitializerProvider(effects: ProviderEffects(isAsync: true, isThrowing: true))
            )
        )
        let use = InjectedUseRecord(
            typeKey: "UserRepository",
            macroName: "@Injected",
            location: makeLocation()
        )

        let result = buildOutput(
            types: [],
            values: [],
            resolutions: [repository],
            injectedUses: [use]
        )

        #expect(result.diagnostics.contains { $0.message.contains("@Injected cannot resolve it") })
    }

    @Test("parameterized providers generate Injected overloads and inject wrappers")
    func parameterizedProvidersGenerateInjectedOverloads() {
        let tokenProvider = makeStaticProvider(
            name: "seeded",
            parameters: [makeParameter(label: "seed", name: "seed", typeKey: "Int", typeName: "Int")]
        )
        let resolution = makeResolution(
            typeName: "SeededToken",
            injectableKey: "SeededToken",
            provider: .explicit(tokenProvider)
        )

        let result = buildOutput(types: [], values: [], resolutions: [resolution])

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.contains("macro Injected(seed: Int)"))
        #expect(result.output.contains("static func seeded(seed: Int) -> SeededToken"))
        #expect(result.output.contains("return SeededToken.seeded(seed: seed)"))
        #expect(result.output.contains("static func inject(seed: Int) -> SeededToken"))
    }

    @Test("providers with only defaulted dependencies still generate callable functions")
    func providersWithDefaultedDependenciesGenerateFunctions() {
        let apiService = makeResolution(
            typeName: "ApiService",
            injectableKey: "ApiServicing",
            provider: .explicit(makeInitializerProvider()),
            isSingleton: true
        )
        let logger = makeResolution(
            typeName: "Logger",
            injectableKey: "Logger",
            provider: .explicit(makeInitializerProvider())
        )
        let live = makeResolution(
            typeName: "LiveUserService",
            injectableKey: "UserService",
            provider: .explicit(
                makeStaticProvider(
                    name: "live",
                    parameters: [
                        makeParameter(label: "apiService", name: "apiService", typeKey: "ApiServicing", typeName: "ApiServicing"),
                        makeParameter(label: "logger", name: "logger", typeKey: "Logger", typeName: "Logger")
                    ]
                )
            )
        )

        let result = buildOutput(types: [], values: [], resolutions: [apiService, logger, live])

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.contains("static func live(apiService: ApiServicing = Zerk<ApiServicing>.inject(), logger: Logger = Zerk<Logger>.inject()) -> UserService"))
        #expect(result.output.contains("return LiveUserService.live(apiService: apiService, logger: logger)"))
        #expect(result.output.contains("static func inject() -> UserService"))
        #expect(result.output.contains("live()"))
    }

    @Test("injectable values require matching parameter names")
    func injectableValuesRequireMatchingParameterNames() {
        let baseUrl = InjectableValueRecord(
            name: "baseUrl",
            typeKey: "String",
            typeName: "String",
            bodyText: #""api.example.com""#,
            location: makeLocation()
        )
        let apiService = makeResolution(
            typeName: "ApiService",
            injectableKey: "ApiServicing",
            provider: .explicit(makeInitializerProvider(
                parameters: [makeParameter(label: "baseUrl", name: "baseUrl", typeKey: "String", typeName: "String")]
            ))
        )
        let userRepository = makeResolution(
            typeName: "UserRepository",
            injectableKey: "UserRepositing",
            provider: .explicit(makeInitializerProvider(
                parameters: [
                    makeParameter(label: "apiService", name: "apiService", typeKey: "ApiServicing", typeName: "ApiServicing"),
                    makeParameter(label: "userId", name: "userId", typeKey: "String", typeName: "String")
                ]
            ))
        )

        let result = buildOutput(
            types: [],
            values: [baseUrl],
            resolutions: [apiService, userRepository]
        )

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.contains("static func apiService(baseUrl: String = Zerk<String>.baseUrl) -> ApiServicing"))
        #expect(result.output.contains("static func userRepository(apiService: ApiServicing = Zerk<ApiServicing>.inject(), userId: String) -> UserRepositing"))
        #expect(result.output.contains("static func inject(userId: String) -> UserRepositing"))
        #expect(result.output.contains("macro Injected(userId: String)"))
        #expect(result.output.contains("userId: String = Zerk<String>.baseUrl") == false)
    }

    @Test("competing types with no primary are an error")
    func competingTypesWithoutPrimaryAreAnError() {
        let live = makeResolution(
            typeName: "LiveLoader",
            injectableKey: "Loading",
            provider: .explicit(makeStaticProvider(name: "live"))
        )
        let mock = makeResolution(
            typeName: "MockLoader",
            injectableKey: "Loading",
            provider: .explicit(makeStaticProvider(name: "mock", location: makeLocation(line: 20)))
        )

        let diagnostics = electionDiagnostics([live, mock])

        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .error)
        #expect(diagnostics[0].message.contains("Multiple types are injectable under 'Loading' (LiveLoader, MockLoader) and none is primary"))
        #expect(diagnostics[0].message.contains("@Injectable(primary: true)"))
    }

    @Test("a primary type wins the key while the others stay as named members")
    func primaryTypeWinsTheKey() {
        let live = makeResolution(
            typeName: "LiveLoader",
            injectableKey: "Loading",
            provider: .explicit(makeStaticProvider(name: "live")),
            isTypePrimary: true
        )
        let mock = makeResolution(
            typeName: "MockLoader",
            injectableKey: "Loading",
            provider: .explicit(makeStaticProvider(name: "mock", location: makeLocation(line: 20)))
        )

        #expect(electionDiagnostics([live, mock]).isEmpty)

        let result = buildOutput(types: [], values: [], resolutions: [live, mock])

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.contains("static var live: Loading"))
        #expect(result.output.contains("static var mock: Loading"))
        #expect(result.output.contains("static func inject() -> Loading"))
        #expect(result.output.contains("        live"))
    }

    @Test("a losing type needs no primary among its own providers")
    func losingTypeNeedsNoProviderPrimary() {
        let live = makeResolution(
            typeName: "LiveLoader",
            injectableKey: "Loading",
            provider: .explicit(makeStaticProvider(name: "live")),
            isTypePrimary: true
        )
        let empty = makeResolution(
            typeName: "MockLoader",
            injectableKey: "Loading",
            provider: .explicit(makeStaticProvider(name: "empty", location: makeLocation(line: 20)))
        )
        let failing = makeResolution(
            typeName: "MockLoader",
            injectableKey: "Loading",
            provider: .explicit(makeStaticProvider(name: "failing", location: makeLocation(line: 30)))
        )

        #expect(electionDiagnostics([live, empty, failing]).isEmpty)

        let result = buildOutput(types: [], values: [], resolutions: [live, empty, failing])

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.contains("static var empty: Loading"))
        #expect(result.output.contains("static var failing: Loading"))
        #expect(result.output.contains("static func inject() -> Loading"))
    }

    @Test("the winning type must pick one of its own providers")
    func winningTypeMustPickAProvider() {
        let empty = makeResolution(
            typeName: "Loader",
            injectableKey: "Loading",
            provider: .explicit(makeStaticProvider(name: "empty"))
        )
        let failing = makeResolution(
            typeName: "Loader",
            injectableKey: "Loading",
            provider: .explicit(makeStaticProvider(name: "failing", location: makeLocation(line: 20)))
        )

        let diagnostics = electionDiagnostics([empty, failing])

        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].message.contains("'Loader' declares multiple providers for 'Loading' and none is primary"))
        #expect(diagnostics[0].message.contains("@InjectableProviding(primary: true)"))
        // Reported against the second provider, so the first stays the one the
        // developer is being asked to keep.
        #expect(diagnostics[0].location.line == 20)
    }

    @Test("two primary providers on one type are an error")
    func twoPrimaryProvidersAreAnError() {
        let live = makeResolution(
            typeName: "Loader",
            injectableKey: "Loading",
            provider: .explicit(makeStaticProvider(name: "live", isPrimary: true))
        )
        let cached = makeResolution(
            typeName: "Loader",
            injectableKey: "Loading",
            provider: .explicit(makeStaticProvider(name: "cached", location: makeLocation(line: 20), isPrimary: true))
        )

        let diagnostics = electionDiagnostics([live, cached])

        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].message.contains("'Loader' declares multiple primary providers for 'Loading'"))
    }

    @Test("a primary provider backs inject while its siblings stay callable")
    func primaryProviderBacksInject() {
        let live = makeResolution(
            typeName: "Loader",
            injectableKey: "Loading",
            provider: .explicit(makeStaticProvider(name: "live", isPrimary: true))
        )
        let cached = makeResolution(
            typeName: "Loader",
            injectableKey: "Loading",
            provider: .explicit(makeStaticProvider(name: "cached", location: makeLocation(line: 20)))
        )

        #expect(electionDiagnostics([live, cached]).isEmpty)

        let result = buildOutput(types: [], values: [], resolutions: [live, cached])

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.contains("static var live: Loading"))
        #expect(result.output.contains("static var cached: Loading"))
        #expect(result.output.contains("static func inject() -> Loading"))
        #expect(result.output.contains("        live"))
    }

    @Test("shared injectables publicize their named members as well as inject()")
    func sharedInjectablesPublicizeNamedMembers() {
        // A consuming module reaching one specific member — `@Injected(\\.live)`
        // — needs to see it, so @Shared covers every member for the key rather
        // than inject() alone.
        let sharedService = makeResolution(
            typeName: "LiveService",
            injectableKey: "Service",
            provider: .explicit(makeStaticProvider(name: "live")),
            isTypePrimary: true,
            isShared: true
        )

        let result = buildOutput(types: [], values: [], resolutions: [sharedService])

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.contains("public static var live: Service"))
        #expect(result.output.contains("public static func inject() -> Service"))
    }

    @Test("an unshared injectable keeps its members internal")
    func unsharedInjectableKeepsMembersInternal() {
        let service = makeResolution(
            typeName: "LiveService",
            injectableKey: "Service",
            provider: .explicit(makeStaticProvider(name: "live")),
            isTypePrimary: true
        )

        let result = buildOutput(types: [], values: [], resolutions: [service])

        #expect(!result.output.contains("public static"))
    }

    @Test("@Shared on a non-public key publicizes nothing and warns")
    func sharedOnNonPublicKeyWarns() {
        let sharedService = makeResolution(
            typeName: "LiveService",
            injectableKey: "Service",
            provider: .explicit(makeStaticProvider(name: "live")),
            isTypePrimary: true,
            isShared: true
        )

        let result = buildOutput(
            types: [],
            values: [],
            resolutions: [sharedService],
            moduleAccessLevels: ["Service": false]
        )

        #expect(!result.output.contains("public static"))
        #expect(result.diagnostics.contains {
            $0.severity == .warning && $0.message.contains("@Shared has no effect")
        })
    }

    @Test("async throwing providers generate async throwing wrappers")
    func asyncThrowingProvidersGenerateAsyncThrowingWrappers() {
        let apiManager = makeResolution(
            typeName: "ApiManager",
            injectableKey: "ApiManager",
            provider: .explicit(makeInitializerProvider())
        )
        let userRepository = makeResolution(
            typeName: "UserRepository",
            injectableKey: "UserRepository",
            provider: .explicit(
                makeInitializerProvider(
                    parameters: [makeParameter(label: "manager", name: "manager", typeKey: "ApiManager", typeName: "ApiManager")],
                    effects: ProviderEffects(isAsync: true, isThrowing: true)
                )
            )
        )

        let result = buildOutput(types: [], values: [], resolutions: [apiManager, userRepository])

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.contains("static func userRepository(manager: ApiManager = Zerk<ApiManager>.inject()) async throws -> UserRepository"))
        #expect(result.output.contains("return try await UserRepository(manager: manager)"))
        #expect(result.output.contains("static func inject() async throws -> UserRepository"))
        #expect(result.output.contains("try await userRepository()"))
    }
}

@Suite("ParameterInjection (@injected)")
struct ParameterInjectionTests {

    private func generate(_ source: String) -> GeneratorOutput {
        let collector = SourceCollector()
        collector.walk(Parser.parse(source: source))
        let resolution = ProviderResolver(types: collector.types).resolve()
        let output = buildOutput(
            types: collector.types,
            values: collector.values,
            resolutions: resolution.resolutions,
            moduleAccessLevels: collector.moduleAccessLevels,
            injectedUses: collector.injectedUses,
            markedMembers: collector.markedMembers
        )
        return GeneratorOutput(
            output: output.output,
            diagnostics: collector.diagnostics + resolution.diagnostics + output.diagnostics
        )
    }

    private let loggerFixture = """
    @Injectable
    struct Logger {
        @InjectableProviding
        init() {}
    }

    """

    @Test("marked init parameter on a class generates a convenience overload")
    func markedClassInitGeneratesConvenienceOverload() {
        let result = generate(loggerFixture + """
        final class AuditTrail {
            init(@injected logger: Logger, label: String) {}
        }
        """)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.contains("extension AuditTrail {"))
        #expect(result.output.contains("convenience init(label: String) {"))
        #expect(result.output.contains("self.init(logger: Zerk<Logger>.inject(), label: label)"))
    }

    @Test("marked init parameter on a struct generates a plain extension init")
    func markedStructInitGeneratesPlainInit() {
        let result = generate(loggerFixture + """
        struct Report {
            init(@injected logger: Logger, title: String) {}
        }
        """)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.contains("extension Report {"))
        #expect(result.output.contains("    nonisolated init(title: String) {"))
        #expect(result.output.contains("self.init(logger: Zerk<Logger>.inject(), title: title)"))
    }

    @Test("marked method parameter generates a delegating overload")
    func markedMethodGeneratesOverload() {
        let result = generate(loggerFixture + """
        final class Reporter {
            func report(@injected logger: Logger, message: String) -> Bool { true }
        }
        """)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.contains("func report(message: String) -> Bool {"))
        #expect(result.output.contains("report(logger: Zerk<Logger>.inject(), message: message)"))
    }

    @Test("actor instance method overload inherits actor isolation")
    func actorInstanceMethodOverloadInheritsIsolation() {
        let result = generate(loggerFixture + """
        actor Worker {
            func run(@injected logger: Logger) {}
        }
        """)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.contains("extension Worker {\n    func run() {"))
        #expect(!result.output.contains("nonisolated func run()"))
        #expect(result.output.contains("run(logger: Zerk<Logger>.inject())"))
    }

    @Test("explicitly nonisolated actor method overload stays nonisolated")
    func nonisolatedActorMethodOverloadStaysNonisolated() {
        let result = generate(loggerFixture + """
        actor Worker {
            nonisolated func run(@injected logger: Logger) {}
        }
        """)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.contains("nonisolated func run()"))
    }

    @Test("actor static method overload stays nonisolated")
    func actorStaticMethodOverloadStaysNonisolated() {
        let result = generate(loggerFixture + """
        actor Worker {
            static func run(@injected logger: Logger) {}
        }
        """)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.contains("nonisolated static func run()"))
    }

    @Test("async provider chains yield async overloads")
    func asyncChainYieldsAsyncOverload() {
        let result = generate("""
        @Injectable
        struct Logger {
            @InjectableProviding
            init() async {}
        }

        final class AuditTrail {
            init(@injected logger: Logger, label: String) {}
        }
        """)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.contains("convenience init(label: String) async {"))
        #expect(result.output.contains("self.init(logger: await Zerk<Logger>.inject(), label: label)"))
    }

    @Test("unresolvable marked parameter emits an error")
    func unresolvableMarkedParameterEmitsError() {
        let result = generate("""
        final class AuditTrail {
            init(@injected service: MissingService) {}
        }
        """)

        #expect(result.diagnostics.contains { $0.message.contains("is not injectable in this module") })
    }

    @Test("marked parameter backed by a parametric provider bubbles its arguments")
    func parametricMarkedParameterBubbles() {
        // Used to be an error. The dependency's own requirements now surface on
        // the overload instead, matching how @autoinjected treats the same case.
        let result = generate("""
        @Injectable
        struct Token {
            @InjectableProviding
            init(seed: Int) {}
        }

        final class Consumer {
            init(@injected token: Token) {}
        }
        """)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.contains("convenience init(seed: Int)"))
        #expect(result.output.contains("self.init(token: Zerk<Token>.inject(seed: seed))"))
    }

    @Test("marked parameter with a default value emits an error")
    func markedParameterWithDefaultEmitsError() {
        let result = generate(loggerFixture + """
        final class AuditTrail {
            init(@injected logger: Logger = Logger()) {}
        }
        """)

        #expect(result.diagnostics.contains { $0.message.contains("cannot declare a default value") })
    }

    @Test("private marked member emits an error")
    func privateMarkedMemberEmitsError() {
        let result = generate(loggerFixture + """
        final class AuditTrail {
            private init(@injected logger: Logger) {}
        }
        """)

        #expect(result.diagnostics.contains { $0.message.contains("must be at least internal") })
    }

    @Test("@injected on a property emits a build error")
    func injectedOnPropertyEmitsError() {
        let result = generate("""
        final class Holder {
            @injected var logger: Logger
        }
        """)

        #expect(result.diagnostics.contains { $0.severity == .error && $0.message.contains("Use @Injected for properties") })
    }

    @Test("public type and member produce a public overload")
    func publicMemberProducesPublicOverload() {
        let result = generate(loggerFixture + """
        public final class AuditTrail {
            public init(@injected logger: Logger, label: String) {}
        }
        """)

        #expect(result.diagnostics.isEmpty)
        #expect(result.output.contains("public convenience init(label: String) {"))
    }
}

private func makeTypeRecord(name: String,
                            injectableKeys: [String],
                            sharedKeys: [String] = [],
                            primaryKeys: [String] = [],
                            defaultProviders: [InjectingProvider] = [],
                            typedProviders: [String: [InjectingProvider]] = [:],
                            initializers: [InitializerRecord] = [],
                            isShared: Bool = false,
                            isSingleton: Bool = false) -> TypeRecord {
    TypeRecord(
        name: name,
        injectableKeys: Dictionary(uniqueKeysWithValues: injectableKeys.map { ($0, makeLocation()) }),
        sharedKeys: Dictionary(
            uniqueKeysWithValues: (isShared ? injectableKeys : sharedKeys).map { ($0, makeLocation()) }
        ),
        primaryKeys: Dictionary(uniqueKeysWithValues: primaryKeys.map { ($0, makeLocation()) }),
        defaultProviders: defaultProviders,
        typedProviders: typedProviders,
        initializers: initializers,
        isSingleton: isSingleton
    )
}

private func makeInitializerRecord(parameters: [ParameterRecord] = [],
                                   effects: ProviderEffects = .none,
                                   location: AttributeLocation = makeLocation()) -> InitializerRecord {
    InitializerRecord(parameters: parameters, effects: effects, location: location)
}

private func makeInitializerProvider(parameters: [ParameterRecord] = [],
                                     effects: ProviderEffects = .none,
                                     location: AttributeLocation = makeLocation(),
                                     isolation: ProviderIsolation = .nonisolated,
                                     isPrimary: Bool = false) -> InjectingProvider {
    InjectingProvider(kind: .initializer, parameters: parameters, effects: effects, location: location, isolation: isolation, isPrimary: isPrimary)
}

private func makeStaticProvider(name: String,
                                parameters: [ParameterRecord] = [],
                                effects: ProviderEffects = .none,
                                location: AttributeLocation = makeLocation(),
                                isolation: ProviderIsolation = .nonisolated,
                                isPrimary: Bool = false) -> InjectingProvider {
    InjectingProvider(kind: .staticFunction(name: name), parameters: parameters, effects: effects, location: location, isolation: isolation, isPrimary: isPrimary)
}

private func makeParameter(label: String?,
                           name: String,
                           typeKey: String,
                           typeName: String? = nil) -> ParameterRecord {
    ParameterRecord(label: label, name: name, typeKey: typeKey, typeName: typeName ?? typeKey)
}

private func makeResolution(typeName: String,
                            injectableKey: String,
                            provider: ProviderChoice,
                            isTypePrimary: Bool = false,
                            isShared: Bool = false,
                            isSingleton: Bool = false) -> ProviderResolution {
    ProviderResolution(
        typeName: typeName,
        injectableKey: injectableKey,
        provider: provider,
        isTypePrimary: isTypePrimary,
        isShared: isShared,
        isSingleton: isSingleton
    )
}

/// Builds generated output from hand-written resolutions, electing the primary
/// per key exactly as the real pipeline does.
///
/// Tests construct resolutions directly rather than parsing source, but which
/// provider backs `inject()` is `ProviderResolver`'s decision — restating those
/// rules here would let the two drift apart silently.
private func buildOutput(types: [TypeRecord] = [],
                         values: [InjectableValueRecord] = [],
                         resolutions: [ProviderResolution],
                         moduleAccessLevels: [String: Bool] = [:],
                         injectedUses: [InjectedUseRecord] = [],
                         markedMembers: [MarkedMemberRecord] = []) -> GeneratorOutput {
    GeneratorOutputBuilder(
        types: types,
        values: values,
        resolutions: resolutions,
        primaryResolutions: ProviderResolver.electPrimaries(among: resolutions).primaries,
        moduleAccessLevels: moduleAccessLevels,
        injectedUses: injectedUses,
        markedMembers: markedMembers
    ).build()
}

/// The diagnostics `ProviderResolver` raises while electing primaries, for
/// tests that assert on ambiguity rather than on generated text.
private func electionDiagnostics(_ resolutions: [ProviderResolution]) -> [CodegenDiagnostic] {
    ProviderResolver.electPrimaries(among: resolutions).diagnostics
}

private func makeLocation(line: Int = 1, column: Int = 1) -> AttributeLocation {
    AttributeLocation(filePath: "/tmp/Test.swift", line: line, column: column)
}
