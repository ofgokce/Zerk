import Zerk

@Injectable
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
@Injectable
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
    @Injectable(.referenced)
    nonisolated(unsafe) static var retryLimit: Int = 3
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
