import Zerk

// MARK: - Interjection test doubles
//
// The plugin declares one interjection point per generated member on
// `Zerk<Key>.Interjection`, named — with a raw identifier — after that member's
// signature. A test registers a double against that point for the duration of a
// scope, so nothing leaks between tests and no global toggle is needed.
//
// These helpers stand in for the `#Interject` macro until Phase 4 lands; the
// mechanism underneath is the one the macro will expand to.

struct InterjectedUserService: UserService {
    func requestPath() -> String {
        "interjected/users"
    }

    var loggerSerial: Int { -1 }
}

/// Runs `operation` with a scope of its own, so interjections registered inside
/// are invisible to every other test — which is what lets these run in parallel.
func withInterjections<R>(_ register: () -> Void,
                          operation: () async throws -> R) async rethrows -> R {
    try await Zerk.withInterjections {
        register()
        return try await operation()
    }
}

func interjectUserService() {
    Zerk<UserService>._$interject(\.live) {
        InterjectedUserService()
    }
}

func interjectSeededToken() {
    Zerk<SeededToken>._$interject(\.seeded) {
        SeededToken(value: 999)
    }
}
