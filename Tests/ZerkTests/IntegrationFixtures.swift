import Zerk

@InjectableValue
var baseURL: String {
    "https://api.example.com"
}

protocol ApiServicing: AnyObject {
    var host: String { get }
}

@Singleton
@Injectable<ApiServicing>
final class ApiService: ApiServicing {
    let host: String

    @InjectableProviding
    init(baseURL: String) {
        self.host = baseURL
    }
}

/// Registered as `[String]`, depended on as `Array<String>`. Before type keys
/// were canonicalized these were two different dependencies, and the parameter
/// bubbled up to the caller instead of resolving.
@InjectableValue
var tags: [String] { ["alpha", "beta"] }

protocol Tagging {
    var joined: String { get }
}

@Injectable<any Tagging>
final class Tagger: Tagging {
    let joined: String

    @InjectableProviding
    init(tags: Array<String>) {
        self.joined = tags.joined(separator: ",")
    }
}

/// `Archiving` is a second name for `Tagging`. Without `@ZerkAlias` the two
/// would be separate keys and this consumer's dependency would bubble up to the
/// caller instead of resolving.
@ZerkAlias
typealias Archiving = Tagging

@Injectable
final class ArchiveConsumer {
    let joined: String

    @InjectableProviding
    init(tagger: Archiving) {
        self.joined = tagger.joined
    }
}

/// `apiService` is marked, `baseURL` is not — and `baseURL: String` would
/// otherwise match the `@Injectable var baseURL` value by key *and* name, so
/// this only stays caller-supplied because the provider is in explicit mode.
@Injectable
final class ExplicitConsumer {
    let host: String
    let suffix: String

    @InjectableProviding
    init(@autoinjected apiService: ApiServicing, baseURL: String) {
        self.host = apiService.host
        self.suffix = baseURL
    }
}

/// `SeededToken`'s provider needs a `seed`, so resolving `token` bubbles that
/// requirement up. `@injectable` says this member's own `seed` supplies it, so
/// one parameter serves both instead of being declared twice.
final class SeedSharingConsumer {
    let tokenValue: Int
    let seed: Int

    init(@injected token: SeededToken, @injectable seed: Int) {
        self.tokenValue = token.value
        self.seed = seed
    }
}

/// `retries` would resolve from `RetryPolicy.retryLimit`, but is marked out.
@Injectable
final class RetryHolder {
    let retryLimit: Int

    @InjectableProviding
    init(@noninjected retryLimit: Int) {
        self.retryLimit = retryLimit
    }
}

protocol Reading: AnyObject {
    var id: Int { get }
}

protocol Writing: AnyObject {
    var id: Int { get }
}

/// One singleton under two keys.
///
/// `Zerk<Reading>` and `Zerk<Writing>` are distinct generic specializations with
/// distinct static storage, so storing the instance on them directly built one
/// per key. It lives in `_$zerk_singletons` instead, once per type.
@Singleton
@Injectable<Reading, Writing>
final class Store: Reading, Writing {
    // Test-only counter; the ZerkTests suite is .serialized. Deliberately not
    // reset between tests — the instance outlives any single test, so a count
    // that could be zeroed underneath it would prove nothing.
    nonisolated(unsafe) static var buildCount = 0
    let id: Int

    @InjectableProviding
    init() {
        Self.buildCount += 1
        self.id = Self.buildCount
    }
}

@Injectable
struct Logger {
    // Test-only counter; the ZerkTests suite is .serialized.
    nonisolated(unsafe) static var createdCount = 0
    let serial: Int

    @InjectableProviding
    init() {
        Self.createdCount += 1
        self.serial = Self.createdCount
    }
}

protocol UserService {
    func requestPath() -> String
    var loggerSerial: Int { get }
}

@Injectable<UserService>
final class LiveUserService: UserService {
    // Test-only counter; the ZerkTests suite is .serialized.
    nonisolated(unsafe) static var factoryCount = 0

    let apiService: ApiServicing
    let loggerSerial: Int

    @InjectableProviding
    static func live(apiService: ApiServicing, logger: Logger) -> UserService {
        Self.factoryCount += 1
        return LiveUserService(apiService: apiService, logger: logger)
    }

    init(apiService: ApiServicing, logger: Logger) {
        self.apiService = apiService
        self.loggerSerial = logger.serial
    }

    func requestPath() -> String {
        "\(apiService.host)/users"
    }
}

@Injectable
final class SeededToken {
    // Test-only counter; the ZerkTests suite is .serialized.
    nonisolated(unsafe) static var factoryCount = 0
    let value: Int

    @InjectableProviding
    static func seeded(seed: Int) -> SeededToken {
        Self.factoryCount += 1
        return SeededToken(value: seed + Self.factoryCount)
    }

    init(value: Int) {
        self.value = value
    }
}

protocol Loading {
    var source: String { get }
}

/// One type, three providers for one key. `live` is primary, so it is what
/// `inject()` builds; the others stay reachable as named members.
@Injectable<Loading>(primary: true)
final class Loader: Loading {
    let source: String

    @InjectableProviding<Loading>(primary: true)
    static func live() -> Loading { Loader(source: "live") }

    @InjectableProviding<Loading>
    static func cached() -> Loading { Loader(source: "cached") }

    @InjectableProviding<Loading>
    static func seeded(source: String) -> Loading { Loader(source: source) }

    init(source: String) {
        self.source = source
    }
}

/// A second type under the same key. `Loader` claims it with
/// `@Injectable<Loading>(primary: true)` above, so this one contributes a named
/// member only — and needs no primary among its own providers.
@Injectable<Loading>
final class NullLoader: Loading {
    let source = "null"

    @InjectableProviding<Loading>
    static func silent() -> Loading { NullLoader() }

    @InjectableProviding<Loading>
    static func noisy() -> Loading { NullLoader() }

    init() {}
}

/// Exercises the remaining `@Injectable` / `@InjectableProviding` overloads against
/// the real macros: the non-generic `primary:` forms, and the value-only
/// `ValueInjectionMethod` form.
enum RetryPolicy {
    @InjectableValue(.referenced)
    nonisolated(unsafe) static var retryLimit: Int = 3
}

// MARK: - Effectful and parametric values

/// An effectful value against the real macros. `@Injected` and key paths cannot
/// reach it — the same limits an effectful provider carries — so it is resolved
/// through a provider parameter.
@InjectableValue
var sessionToken: String {
    get async throws {
        try await Task.sleep(nanoseconds: 1_000)
        return "session-token"
    }
}

@Injectable
final class TokenHolder {
    let token: String

    @InjectableProviding
    init(sessionToken: String) {
        self.token = sessionToken
    }
}

/// A parametric value: `logger` resolves from the graph, `label` bubbles to the
/// consumer's `inject(label:)`.
enum Formatting {
    @InjectableValue
    static func caption(logger: Logger, label: String) -> String {
        "\(label)#\(logger.serial)"
    }
}

@Injectable
final class CaptionHolder {
    let caption: String

    @InjectableProviding
    init(caption: String) {
        self.caption = caption
    }
}

/// Exercises `@ImportedInjectableValue` against the real macro. Named so that
/// nothing resolves through it — the point here is that the attribute parses and
/// expands, and that the getter type-checks against a member that exists. Its
/// cross-module behaviour is covered by `ImportedInjectableValueTests`.
private enum ZerkImports {
    @ImportedInjectableValue
    static var importedRetryLimit: Int { Zerk<Int>.retryLimit }
}

// MARK: - public:

public protocol Exporting: AnyObject {
    var name: String { get }
}

/// Every `public:` overload against the real macros — `public` has to survive
/// as an argument label through parsing, macro overload resolution, and the
/// plugin's own reading of the attribute.
@Injectable<Exporting>(primary: true, public: true)
public final class ExportedService: Exporting {
    public let name = "exported"

    @InjectableProviding
    public init() {}
}

@Injectable(public: true)
public final class BareExportedService {
    @InjectableProviding
    public init() {}
}

@InjectableValue(.copied, public: true)
public let exportedBanner: String = "banner"

@InjectableValues(public: true)
public enum ExportedConstants {
    public static let exportedLimit: Int = 7

    /// States its own answer, so the sweep does not apply.
    @InjectableValue(public: false)
    public static let unexportedTag: String = "tag"
}

@Injectable(primary: true)
final class Reporter {
    let mode: String

    @InjectableProviding(primary: true)
    init() {
        self.mode = "default"
    }

    @InjectableProviding
    init(mode: String) {
        self.mode = mode
    }
}

struct FeedViewModel {
    @Injected
    var userService: UserService
}

struct LoaderConsumer {
    @Injected
    var loader: Loading
}

/// Names a non-primary member with a key path, rather than taking `inject()`.
struct KeyPathLoaderConsumer {
    @Injected(\.cached)
    var loader: Loading
}

protocol Reporting {
    var label: String { get }
}

/// Keyed under both its own type and a protocol, so a consumer can ask for
/// either one.
@Injectable
@Injectable<Reporting>
final class ConsoleReporter: Reporting {
    let label = "console"

    @InjectableProviding
    init() {}
}

/// Resolves the *concrete* key while storing it as the protocol.
struct StatedKeyConsumer {
    @Injected<ConsoleReporter>
    var reporter: Reporting
}

/// Same, with optional storage.
struct StatedKeyOptionalConsumer {
    @Injected<ConsoleReporter>
    var reporter: Reporting?
}

struct EagerTokenConsumer {
    @Injected(seed: 100)
    var seededToken: SeededToken
}

final class LazyTokenConsumer {
    lazy var seededToken: SeededToken = Zerk<SeededToken>.inject(seed: 100)
}

final class SessionOwner {
    @Injected
    var apiService: ApiServicing
}

final class AuditTrail {
    let logger: Logger
    let label: String

    init(@injected logger: Logger, label: String) {
        self.logger = logger
        self.label = label
    }
}

// MARK: - Generic injectables
//
// Registered under their shape (`Codec<#0>`, `Repository<#0>`), emitted as
// members of an unconstrained `extension Zerk` that bind `Injectable` per call.
// The counters prove specializations are genuinely distinct at runtime rather
// than one erased instance handed out twice.

/// The build counter cannot live on `Codec` itself: static stored properties
/// are illegal in a generic type, which is the same fact that makes a generic
/// `@Singleton` impossible.
enum CodecCounter {
    nonisolated(unsafe) static var builds: [String] = []
}

@Injectable
struct Codec<Element> {
    let logger: Logger

    @InjectableProviding
    init(logger: Logger) {
        self.logger = logger
        CodecCounter.builds.append(String(describing: Element.self))
    }
}

@Injectable
struct Repository<Element> {
    let codec: Codec<Element>
    let logger: Logger

    @InjectableProviding
    init(codec: Codec<Element>, logger: Logger) {
        self.codec = codec
        self.logger = logger
    }
}

/// A concrete consumer naming one specialization. Nothing registers
/// `Repository<String>` — matching it to `Repository<#0>` is what turns this
/// parameter from caller-supplied into resolved.
@Injectable
struct StringFeed {
    let repository: Repository<String>

    @InjectableProviding
    init(repository: Repository<String>) {
        self.repository = repository
    }
}

// MARK: - A generic type under a concrete key
//
// The other generic mode: `any Describing` erases X, so the member recovers it
// from its own argument and the result is erased into the key. The key stays
// concrete, so unlike a generic key this one keeps its interjection point.

protocol Describing {
    var describedValue: String { get }
}

@Injectable<any Describing>
struct ValueReport<X>: Describing {
    let value: X
    var describedValue: String { "\(value)" }

    @InjectableProviding
    init(_ value: X) {
        self.value = value
    }
}

// MARK: - A parameterized existential key
//
// `parameterized: true` applies the type's own parameters to the protocol's
// primary associated types, so the key is `any Pairing<A, B>` rather than a
// plain erased `any Pairing`. Gated on iOS 16 / macOS 13, which is where
// parameterized existentials arrived.

protocol Pairing<A, B> {
    associatedtype A
    associatedtype B
    var described: String { get }
}

@Injectable<any Pairing>(parameterized: true)
struct Pair<A, B>: Pairing {
    let first: A
    let second: B
    var described: String { "\(first)|\(second)" }

    @InjectableProviding
    init(_ first: A, _ second: B) {
        self.first = first
        self.second = second
    }
}
