import Testing

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
