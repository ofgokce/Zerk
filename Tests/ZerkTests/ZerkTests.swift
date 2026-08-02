import Testing
import Zerk

@Suite("Zerk Macro Integration", .serialized)
struct ZerkTests {
    @Test("unique typed injection resolves dependencies")
    func protocolInjectionFlow() throws {
        resetFixtureState()

        let model = FeedViewModel()
        let first = try #require(model.userService as? LiveUserService)
        let second = try #require(model.userService as? LiveUserService)

        #expect(first.requestPath() == "https://api.example.com/users")
        #expect(second.requestPath() == "https://api.example.com/users")
        #expect(first.loggerSerial == 1)
        #expect(second.loggerSerial == 1)
        #expect(LiveUserService.factoryCount == 1)
        #expect(Logger.createdCount == 1)
    }

    @Test("@Injected resolves parameterized values eagerly")
    func eagerParameterizedInjectionFlow() {
        resetFixtureState()

        let consumer = EagerTokenConsumer()
        let first = consumer.seededToken.value
        let second = consumer.seededToken.value

        #expect(first == 101)
        #expect(second == 101)
        #expect(SeededToken.factoryCount == 1)
    }

    @Test("lazy var with Zerk.inject() resolves parameterized values on first access")
    func lazyParameterizedInjectionFlow() {
        resetFixtureState()

        let consumer = LazyTokenConsumer()

        #expect(SeededToken.factoryCount == 0)
        let first = consumer.seededToken.value
        let second = consumer.seededToken.value

        #expect(first == 101)
        #expect(second == 101)
        #expect(SeededToken.factoryCount == 1)
    }

    @Test("singleton injectable is shared across consumers")
    func singletonIsShared() {
        resetFixtureState()

        let firstOwner = SessionOwner()
        let secondOwner = SessionOwner()

        #expect(firstOwner.apiService === secondOwner.apiService)
    }

    @Test("a dependency spelled Array<String> resolves an [String] value")
    func canonicalizedKeysResolve() {
        resetFixtureState()

        // No argument to pass: `Array<String>` matched the `[String]` value, so
        // inject() resolves the whole graph itself.
        let tagger = Zerk<any Tagging>.inject()

        #expect(tagger.joined == "alpha,beta")
    }

    @Test("a singleton injectable under two keys is one instance")
    func singletonIsSharedAcrossKeys() {
        resetFixtureState()

        let reader = Zerk<Reading>.inject()
        let writer = Zerk<Writing>.inject()

        #expect(reader === writer)
        #expect(reader.id == writer.id)

        // Resolving again through either key must not build a second instance.
        // Compared against a captured count rather than a literal, so the
        // assertion holds wherever this lands in the run order.
        let built = Store.buildCount
        #expect(Zerk<Reading>.inject() === reader)
        #expect(Zerk<Writing>.inject() === reader)
        #expect(Store.buildCount == built)
    }

    @Test("@injected parameter generates a wired overload")
    func injectedParameterGeneratesWiredOverload() {
        resetFixtureState()

        let trail = AuditTrail(label: "audit")

        #expect(trail.label == "audit")
        #expect(trail.logger.serial == 1)
        #expect(Logger.createdCount == 1)

        let manual = AuditTrail(logger: trail.logger, label: "manual")
        #expect(manual.logger.serial == 1)
        #expect(Logger.createdCount == 1)
    }

    @Test("every provider for a key becomes a member, and the primary backs inject")
    func multipleProvidersPerKey() {
        resetFixtureState()

        // The primary provider on the primary type.
        #expect(LoaderConsumer().loader.source == "live")
        #expect(Zerk<Loading>.inject().source == "live")

        // Its siblings on the same type.
        #expect(Zerk<Loading>.live.source == "live")
        #expect(Zerk<Loading>.cached.source == "cached")
        #expect(Zerk<Loading>.seeded(source: "custom").source == "custom")

        // And the losing type's providers, which need no primary of their own.
        #expect(Zerk<Loading>.silent.source == "null")
        #expect(Zerk<Loading>.noisy.source == "null")
    }

    @Test("the non-generic primary overloads resolve through the real macros")
    func nonGenericPrimaryOverloads() {
        resetFixtureState()

        // Two marked initializers: same member name, told apart by parameters.
        #expect(Zerk<Reporter>.inject().mode == "default")
        #expect(Zerk<Reporter>.reporter(mode: "verbose").mode == "verbose")

        // @Injectable(.referenced) reads through to the declaration.
        RetryPolicy.retryLimit = 7
        #expect(Zerk<Int>.retryLimit == 7)
        RetryPolicy.retryLimit = 3
    }

    @Test("interjection overrides injection with mock type")
    func interjectionOverridesInjection() throws {
        resetFixtureState()
        InterjectionToggles.userService = true

        let model = FeedViewModel()
        let service = model.userService

        #expect(service is InterjectedUserService)
        #expect(service.requestPath() == "interjected/users")
        #expect(service.loggerSerial == -1)
    }

    @Test("interjection overrides parameterized injection with inlined value")
    func interjectionOverridesParameterizedInjection() {
        resetFixtureState()
        InterjectionToggles.seededToken = true

        let consumer = EagerTokenConsumer()
        let value = consumer.seededToken.value

        #expect(value == 999)
        #expect(SeededToken.factoryCount == 0)
    }

}

private func resetFixtureState() {
    Logger.createdCount = 0
    LiveUserService.factoryCount = 0
    SeededToken.factoryCount = 0
    InterjectionToggles.userService = false
    InterjectionToggles.seededToken = false
}
