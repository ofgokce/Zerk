//
//  ZerkInterjections.swift
//  Zerk
//

import Testing
import Zerk

/// Gives every test its own interjection scope, optionally starting from a set
/// of interjections they all share.
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
/// ``ZerkInterjector/processDefault``. That is the whole reason this exists:
/// Swift Testing runs tests in parallel, and a shared set of interjections would
/// let one test's double surface in another, including tests that never mention
/// interjection.
///
/// Because it is a trait *and* an ordinary value, a set worth sharing can be
/// named once and applied wherever it is wanted:
///
/// ```swift
/// let apiDoubles = ZerkInterjections {
///     #Interject<ApiServicing>(with: MockApi())
///     #Interject(\.staging, with: Session.mock)
/// }
///
/// @Suite(apiDoubles)
/// struct CheckoutTests { … }
///
/// @Suite(apiDoubles)
/// struct FeedTests { … }
/// ```
///
/// `isRecursive` is `true`, so applying it to a suite gives each test its own
/// scope rather than wrapping the suite in one — which is what makes the tests
/// inside independent rather than merely separated from everything outside.
public struct ZerkInterjections: TestTrait, SuiteTrait, TestScoping {

    /// Applied to every scope this opens, before the test runs. A test may add
    /// to or replace them; its own registrations win, since they land in the
    /// same scope afterwards.
    private let interjections: (@Sendable () -> Void)?

    public var isRecursive: Bool { true }

    /// Interjections every test applying this starts from.
    ///
    /// The closure runs once per *test* rather than once per suite, so the
    /// doubles are rebuilt for each and nothing carries state across — which is
    /// what makes one of these safe to share between suites.
    public init(_ interjections: @escaping @Sendable () -> Void) {
        self.interjections = interjections
    }

    /// A fresh scope and nothing else. Spelled `.zerk` at a use site.
    init() {
        self.interjections = nil
    }

    public func provideScope(for test: Test,
                             testCase: Test.Case?,
                             performing function: () async throws -> Void) async throws {
        try await Zerk.withInterjections {
            interjections?()
            try await function()
        }
    }
}

public extension Trait where Self == ZerkInterjections {

    /// A fresh interjection scope per test.
    static var zerk: Self {
        ZerkInterjections()
    }

    /// A fresh scope per test, starting from interjections every test in the
    /// suite shares.
    ///
    /// ```swift
    /// @Suite(.zerk { #Interject<ApiServicing>(with: MockApi()) })
    /// struct FeedTests { … }
    /// ```
    ///
    /// The same thing ``ZerkInterjections/init(_:)`` builds, spelled inline. Use
    /// the initializer when the set is worth naming and sharing.
    static func zerk(_ interjections: @escaping @Sendable () -> Void) -> Self {
        ZerkInterjections(interjections)
    }
}
