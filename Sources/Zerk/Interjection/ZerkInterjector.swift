//
//  ZerkInterjector.swift
//  Zerk
//

import Foundation

/// The interjections in force for the current task — the doubles standing in for
/// what the graph would otherwise build.
///
/// Deliberately a **class**. The task local holds a reference, so `#Interject`
/// can add to the set in the middle of a test without wrapping everything after
/// it in a closure. Isolation comes from each test being handed its own set, not
/// from rebinding a value.
///
/// Two dimensions, the more specific first:
///
/// 1. **by key path** — one member, named by a key path to its
///    ``Zerk/Interjection`` namespace. The plugin declares one point per
///    generated member, so this reaches every member, parameterized and
///    overloaded alike.
/// 2. **by key** — every member of a key at once, for `#Interject<Key>`.
///
/// A key path is the identity rather than an encoded name, which settles two
/// problems no string could. `@ZerkAlias` groups fold on their own, because
/// `Zerk<Persisting>` and `Zerk<Storing>` are one specialization. And a mismatch
/// between what a test names and what the plugin emitted is a *compile* error at
/// the interjection — `type 'Zerk<…>' has no member 'seeded(seed: Int)'` —
/// rather than a lookup that silently finds nothing.
public final class ZerkInterjector: @unchecked Sendable {

    /// The interjections in force for the current task.
    ///
    /// Outside any scope this is ``processDefault``, which refuses registration
    /// unless the process really is the scope — see there.
    @TaskLocal
    public static var current = processDefault

    /// The instance in force when nothing has established a scope.
    ///
    /// Registering into it is a mistake almost everywhere: a task local read
    /// outside a binding reaches one shared object, so an interjection made
    /// there leaks into every other test running concurrently — including tests
    /// that never mention interjection, which then fail somewhere unrelated.
    /// So it traps, naming the fix.
    ///
    /// A SwiftUI preview is the exception, because there the process genuinely
    /// *is* the scope. A task local cannot serve one: SwiftUI constructs child
    /// views and re-invokes `body` long after the `#Preview` closure has
    /// returned, by which point any binding has unwound.
    public static let processDefault = ZerkInterjector(allowsUnscopedRegistration: isRunningInPreview)

    /// Whether this process is rendering SwiftUI previews.
    ///
    /// Xcode sets `XCODE_RUNNING_FOR_PREVIEWS`; the process-name check is a
    /// fallback, since neither is API and the variable has moved before.
    static var isRunningInPreview: Bool {
        let info = ProcessInfo.processInfo
        if info.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return true
        }
        return info.processName.contains("PreviewShell")
    }

    /// `false` only for ``processDefault`` outside a preview. Every instance a
    /// scope hands out is scoped by construction, so registration is free.
    private let allowsUnscopedRegistration: Bool
    private let lock = NSLock()
    private var byKeyPath: [AnyKeyPath: @Sendable () -> Any] = [:]
    private var byKey: [ObjectIdentifier: @Sendable () -> Any] = [:]

    /// Internal because an instance nobody installs as ``current`` is inert:
    /// nothing reads it, so registering into it silently does nothing.
    /// ``Zerk/withInterjections(_:)`` is the only thing that should make one,
    /// and it binds what it makes.
    init() {
        allowsUnscopedRegistration = true
    }

    private init(allowsUnscopedRegistration: Bool) {
        self.allowsUnscopedRegistration = allowsUnscopedRegistration
    }

    /// Refuses a registration that would leak, rather than letting it surface as
    /// an unrelated test failing later.
    private func checkScoped() {
        guard !allowsUnscopedRegistration else {
            return
        }
        preconditionFailure("""
            Zerk: interjected outside a scope, which would leak into every test \
            running alongside this one. Use the `.zerk` trait on the suite, or \
            wrap the work in `Zerk.withInterjections { }`. Unscoped interjection \
            is allowed only in SwiftUI previews, where the process is the scope.
            """)
    }

    // MARK: - Registration
    //
    // Internal: both take `Any`, so reaching them directly would drop the one
    // guarantee the scheme rests on — that a double is typed against the key it
    // stands in for. `Zerk<Key>._$interject` is where that is enforced, and
    // `#Interject` is where a developer meets it.

    func interject(_ keyPath: AnyKeyPath, _ body: @escaping @Sendable () -> Any) {
        checkScoped()
        lock.lock()
        defer { lock.unlock() }
        byKeyPath[keyPath] = body
    }

    func interject(_ key: ObjectIdentifier, _ body: @escaping @Sendable () -> Any) {
        checkScoped()
        lock.lock()
        defer { lock.unlock() }
        byKey[key] = body
    }

    // MARK: - Lookup
    //
    // `@usableFromInline` rather than `public`: both are read from
    // `Zerk._$interjected`, whose body is `@inlinable` and so may only name
    // declarations visible outside the module. That is a requirement of
    // inlining, not an invitation — nothing outside Zerk has a key path and an
    // `ObjectIdentifier` to look one up with.

    /// The blanket double for a key, ignoring the per-member dimension.
    ///
    /// For members that have no point to name — see ``Zerk/_$interjected()``.
    /// Everything else goes through ``value(for:of:as:)``, which consults this
    /// as its fallback anyway.
    @usableFromInline
    func value<V>(of key: ObjectIdentifier, as _: V.Type = V.self) -> V? {
        lock.lock()
        let body = byKey[key]
        lock.unlock()
        return body?() as? V
    }

    /// The double standing in for a member, or `nil` to build the real thing.
    ///
    /// A member interjection beats a blanket over its key, so a blanket can set
    /// a baseline for a preview while one member stays pinned to something
    /// exact.
    @usableFromInline
    func value<V>(for keyPath: AnyKeyPath,
                  of key: ObjectIdentifier,
                  as _: V.Type = V.self) -> V? {
        lock.lock()
        let body = byKeyPath[keyPath] ?? byKey[key]
        lock.unlock()

        guard let body else {
            return nil
        }
        guard let typed = body() as? V else {
            // Unreachable by construction: every registration is typed against
            // the key, and a generated member always returns its key. Reaching
            // here means Zerk emitted a point the registration did not agree
            // with, which is a bug in Zerk rather than in the test.
            assertionFailure("Zerk: an interjection produced the wrong type.")
            return nil
        }
        return typed
    }

    /// Drops every interjection.
    ///
    /// Mostly for a preview that wants a clean slate, since a preview's
    /// interjections outlive the view that made them. Tests should take a fresh
    /// scope instead — under XCTest, by overriding `invokeTest()` to wrap
    /// `super.invokeTest()` in ``Zerk/withInterjections(_:)``.
    public func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        byKeyPath.removeAll()
        byKey.removeAll()
    }
}

public extension Zerk where Injectable == Never {

    /// Runs `operation` with a scope of its own, so anything interjected inside
    /// is invisible to everything outside — including tests running alongside.
    ///
    /// Spelled on `Zerk<Never>` so it reads as `Zerk.withInterjections { … }`
    /// without naming a key, since a scope covers every key at once.
    static func withInterjections<R>(_ operation: () async throws -> R) async rethrows -> R {
        try await ZerkInterjector.$current.withValue(ZerkInterjector(), operation: operation)
    }

    /// The synchronous form, for XCTest's `invokeTest()` and for any test body
    /// that never suspends.
    static func withInterjections<R>(_ operation: () throws -> R) rethrows -> R {
        try ZerkInterjector.$current.withValue(ZerkInterjector(), operation: operation)
    }
}
