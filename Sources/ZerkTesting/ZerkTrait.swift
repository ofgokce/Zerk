//
//  ZerkTrait.swift
//  Zerk
//

import Testing
import Zerk

/// Gives every test its own interjection scope.
///
/// ```swift
/// @Suite(.zerk)
/// struct FeedTests {
///     @Test func showsCachedItems() {
///         #Interject(\.live, with: MockFeedService())
///         …
///     }
/// }
/// ```
///
/// Without it, `#Interject` outside a scope traps rather than leaking — see
/// ``ZerkInterjections/processDefault``. That is the whole reason this exists:
/// Swift Testing runs tests in parallel, and a shared set of interjections would
/// let one test's double surface in another, including tests that never mention
/// interjection.
///
/// `isRecursive` is `true`, so applying it to a suite gives each test its own
/// scope rather than wrapping the suite in one — which is what makes the tests
/// inside independent rather than merely separated from everything outside.
public struct ZerkTrait: TestTrait, SuiteTrait, TestScoping {

    /// Interjections applied to every scope this trait opens, before the test
    /// runs. A test may add to or replace them; its own registrations win, since
    /// they land in the same scope afterwards.
    private let seed: (@Sendable () -> Void)?

    public var isRecursive: Bool { true }

    init(seed: (@Sendable () -> Void)?) {
        self.seed = seed
    }

    public func provideScope(for test: Test,
                             testCase: Test.Case?,
                             performing function: () async throws -> Void) async throws {
        try await Zerk.withInterjections {
            seed?()
            try await function()
        }
    }
}

public extension Trait where Self == ZerkTrait {

    /// A fresh interjection scope per test.
    static var zerk: Self {
        ZerkTrait(seed: nil)
    }

    /// A fresh scope per test, seeded with interjections every test in the suite
    /// shares.
    ///
    /// ```swift
    /// @Suite(.zerk { #Interject<ApiServicing>(with: MockApi()) })
    /// struct FeedTests { … }
    /// ```
    ///
    /// The closure runs once per test rather than once per suite, so the doubles
    /// are rebuilt for each and nothing carries state across.
    static func zerk(_ seed: @escaping @Sendable () -> Void) -> Self {
        ZerkTrait(seed: seed)
    }
}
