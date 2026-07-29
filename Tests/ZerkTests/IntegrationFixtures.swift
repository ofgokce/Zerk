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

    @Providing
    init(baseURL: String) {
        self.host = baseURL
    }
}

@Injectable
struct Logger {
    // Test-only counter; the ZerkTests suite is .serialized.
    nonisolated(unsafe) static var createdCount = 0
    let serial: Int

    @Providing
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

    @Providing
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

    @Providing
    static func seeded(seed: Int) -> SeededToken {
        Self.factoryCount += 1
        return SeededToken(value: seed + Self.factoryCount)
    }

    init(value: Int) {
        self.value = value
    }
}

struct FeedViewModel {
    @Injected
    var userService: UserService
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
