import Zerk

// MARK: - Interjection test doubles
//
// The Zerk plugin generates an `Interjecting<Key>` protocol per injectable key,
// mirroring each generated injector member. A test suite overrides an
// implementation by conditionally conforming `Zerk` to that protocol and
// returning a double — or `nil` to fall through to the real provider. The
// toggles below keep the non-interjection tests resolving the real objects.

enum InterjectionToggles {
    nonisolated(unsafe) static var userService = false
    nonisolated(unsafe) static var seededToken = false
}

struct InterjectedUserService: UserService {
    func requestPath() -> String {
        "interjected/users"
    }

    var loggerSerial: Int { -1 }
}

extension Zerk: InterjectingUserService where T == UserService {
    static func interjectedLive(apiService: ApiServicing, logger: Logger) -> UserService? {
        InterjectionToggles.userService ? InterjectedUserService() : nil
    }
}

extension Zerk: InterjectingSeededToken where T == SeededToken {
    static func interjectedSeeded(seed: Int) -> SeededToken? {
        InterjectionToggles.seededToken ? SeededToken(value: 999) : nil
    }
}
