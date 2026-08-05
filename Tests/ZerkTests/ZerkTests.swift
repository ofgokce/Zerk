import Testing
import Zerk

/// Serialized for the *counter* fixtures, not for interjection: several cases
/// assert on shared `static var` construction counts (`Logger.createdCount`,
/// `LiveUserService.factoryCount`) that race when tests run concurrently.
/// Interjection itself is now per-scope and parallel-safe — see
/// `InterjectionStoreTests`, whose suites do run concurrently.
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

    @Test("@Injected<Key> resolves the stated key into a differently typed property")
    func statedKeyResolvesIntoACompatibleProperty() {
        resetFixtureState()

        // The key is the concrete type; the property is the protocol it
        // satisfies. Before, this was rejected as a type mismatch.
        #expect(StatedKeyConsumer().reporter.label == "console")
        #expect(StatedKeyOptionalConsumer().reporter?.label == "console")
    }

    @Test("@Injected with a key path resolves the named member, not the primary")
    func keyPathInjectionPicksTheNamedMember() {
        resetFixtureState()

        // `live` is primary, so a plain @Injected would give "live".
        #expect(LoaderConsumer().loader.source == "live")
        #expect(KeyPathLoaderConsumer().loader.source == "cached")
    }

    @Test("@injectable feeds one parameter to both the member and its dependency")
    func injectableSharesAParameter() {
        resetFixtureState()

        // One `seed`: it reaches SeededToken's provider and the member itself.
        let consumer = SeedSharingConsumer(seed: 100)

        #expect(consumer.seed == 100)
        #expect(consumer.tokenValue == 101)
    }

    @Test("@noninjected keeps a resolvable parameter caller-supplied")
    func nonInjectedOptsOut() {
        resetFixtureState()

        // `RetryPolicy.retryLimit` is injectable and matches by name and type,
        // so without the marker this would take no arguments at all.
        let holder = Zerk<RetryHolder>.inject(retryLimit: 9)

        #expect(holder.retryLimit == 9)
    }

    @Test("@autoinjected resolves marked parameters and leaves the rest alone")
    func autoInjectedSelectsWhatIsResolved() {
        resetFixtureState()

        // `baseURL` is required despite being resolvable — the signature itself
        // is the assertion, since inject() would take no arguments otherwise.
        let consumer = Zerk<ExplicitConsumer>.inject(baseURL: "supplied-by-caller")

        #expect(consumer.host == "https://api.example.com")
        #expect(consumer.suffix == "supplied-by-caller")
    }

    @Test("a @ZerkAlias key resolves from the underlying key's provider")
    func aliasedKeyResolves() {
        resetFixtureState()

        // `Archiving` is a typealias of `Tagging`; nothing is registered under
        // it, so this only resolves because the keys were merged.
        let consumer = Zerk<ArchiveConsumer>.inject()

        #expect(consumer.joined == "alpha,beta")
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
    func interjectionOverridesInjection() async throws {
        resetFixtureState()
        await withInterjections(interjectUserService) {
            let model = FeedViewModel()
            let service = model.userService

            #expect(service is InterjectedUserService)
            #expect(service.requestPath() == "interjected/users")
            #expect(service.loggerSerial == -1)
        }
    }

    @Test("interjection overrides parameterized injection with inlined value")
    func interjectionOverridesParameterizedInjection() async {
        resetFixtureState()
        await withInterjections(interjectSeededToken) {
            let consumer = EagerTokenConsumer()
            let value = consumer.seededToken.value

            #expect(value == 999)
            #expect(SeededToken.factoryCount == 0)
        }
    }

}

private func resetFixtureState() {
    Logger.createdCount = 0
    LiveUserService.factoryCount = 0
    SeededToken.factoryCount = 0
}

// MARK: - Generic injectables

/// Serialized for the same reason as the suite above: two cases assert on
/// `CodecCounter.builds`, a shared record of which specializations were
/// constructed, and it races when they run concurrently.
@Suite("Generic injection", .serialized)
struct GenericInjectionTests {

    @Test("a generic key resolves per specialization")
    func resolvesPerSpecialization() {
        CodecCounter.builds = []

        let strings: Repository<String> = Zerk<Repository<String>>.inject()
        let ints: Repository<Int> = Zerk<Repository<Int>>.inject()

        // Distinct specializations, each built through its own chain.
        #expect(type(of: strings.codec) == Codec<String>.self)
        #expect(type(of: ints.codec) == Codec<Int>.self)
        #expect(CodecCounter.builds == ["String", "Int"])
    }

    @Test("a generic member resolves its dependencies without arguments")
    func resolvesDependenciesUnaided() {
        // `Repository` names a `Codec<Element>` and a `Logger`, and neither is
        // passed here: one resolves through the shape of its own key, the other
        // through an ordinary concrete one. Both loggers are freshly built,
        // since `Logger` is not a singleton in these fixtures — what is under
        // test is that the chain ran at all.
        CodecCounter.builds = []

        let repository: Repository<String> = Zerk<Repository<String>>.inject()

        #expect(CodecCounter.builds == ["String"])
        #expect(repository.logger.serial > 0)
        #expect(repository.codec.logger.serial > 0)
    }

    @Test("a concrete consumer resolves a specialization it never registered")
    func concreteConsumerResolvesASpecialization() {
        // Nothing registers `Repository<String>`; matching it to `Repository<#0>`
        // is what makes this resolve at all.
        let feed: StringFeed = Zerk<StringFeed>.inject()
        #expect(type(of: feed.repository.codec) == Codec<String>.self)
    }

    @Test("the named member is reachable directly, like any other")
    func namedMemberIsReachable() {
        let codec: Codec<Bool> = Zerk<Codec<Bool>>.codec()
        #expect(type(of: codec) == Codec<Bool>.self)
    }
}

@Suite("Generic member, concrete key")
struct ErasedGenericInjectionTests {

    @Test("the member infers its parameter from the argument")
    func inferredFromArgument() {
        let report: any Describing = Zerk<any Describing>.inject(42)
        #expect(report.describedValue == "42")
        #expect(report is ValueReport<Int>)
    }

    @Test("each call may erase a different specialization")
    func differentSpecializationsPerCall() {
        #expect(Zerk<any Describing>.inject("hi") is ValueReport<String>)
        #expect(Zerk<any Describing>.inject(true) is ValueReport<Bool>)
    }

    @Test("the key is concrete, so it is still interjectable", .zerk)
    func stillInterjectable() {
        // A generic *key* has no point yet. This one does, because the point
        // hangs off the key and this key is `any Describing`.
        #Interject<any Describing>(with: ValueReport(0))
        #expect(Zerk<any Describing>.inject(42).describedValue == "0")
    }
}

/// No `@available` needed, and swift-testing would reject one: the package's
/// macOS minimum is 14, above the 13 a parameterized existential requires.
@Suite("Parameterized existential key")
struct ParameterizedKeyInjectionTests {

    @Test("the key carries the specialization, rather than erasing it")
    func keyCarriesTheSpecialization() {
        let pair: any Pairing<Int, String> = Zerk<any Pairing<Int, String>>.inject(1, "a")
        #expect(pair.described == "1|a")
        // Statically `any Pairing<Int, String>`, not a bare `any Pairing`: the
        // associated types survive into the key.
        let first: Int = 1
        #expect(type(of: pair) == Pair<Int, String>.self)
        #expect(first == 1)
    }

    @Test("different specializations are different keys")
    func specializationsAreDistinctKeys() {
        let ints: any Pairing<Int, Int> = Zerk<any Pairing<Int, Int>>.inject(1, 2)
        let mixed: any Pairing<String, Bool> = Zerk<any Pairing<String, Bool>>.inject("x", true)
        #expect(ints.described == "1|2")
        #expect(mixed.described == "x|true")
    }
}

@Suite("Generic key interjection", .zerk)
struct GenericKeyInterjectionTests {

    /// A double whose identity is checkable: `Logger` is not a singleton here,
    /// so a freshly built one always has a serial of its own.
    private func makeDouble<E>(_: E.Type) -> Repository<E> {
        Repository<E>(codec: .init(logger: .init()), logger: .init())
    }

    @Test("a generic key interjects per specialization, by key path")
    func byKeyPathPerSpecialization() {
        let double = makeDouble(String.self)
        #Interject(\.`repository`, with: double)

        // The point is scoped by the generated marker, so it reaches exactly
        // `Repository`'s specializations...
        let strings: Repository<String> = Zerk<Repository<String>>.inject()
        #expect(strings.logger.serial == double.logger.serial)

        // ...and only the one registered. A sibling is built for real.
        let ints: Repository<Int> = Zerk<Repository<Int>>.inject()
        #expect(ints.logger.serial != double.logger.serial)
    }

    @Test("a blanket reaches a generic key too")
    func blanketOnASpecialization() {
        let double = makeDouble(String.self)
        #Interject<Repository<String>>(with: double)

        let resolved: Repository<String> = Zerk<Repository<String>>.inject()
        #expect(resolved.logger.serial == double.logger.serial)

        // Interjection does not short-circuit resolution: the member's defaults
        // are evaluated before its guard runs, so the real subtree is still
        // built. That is by design and holds for a generic key too.
        CodecCounter.builds = []
        _ = Zerk<Repository<String>>.inject() as Repository<String>
        #expect(CodecCounter.builds == ["String"])
    }

    @Test("a parameterized existential key is reachable by key")
    func parameterizedExistentialByKey() {
        #Interject<any Pairing<Int, String>>(with: Pair(99, "z"))
        let pair: any Pairing<Int, String> = Zerk<any Pairing<Int, String>>.inject(1, "a")
        #expect(pair.described == "99|z")
        // A different specialization resolves for real.
        let other: any Pairing<Bool, Bool> = Zerk<any Pairing<Bool, Bool>>.inject(true, false)
        #expect(other.described == "true|false")
    }
}
