//
//  InterjectMacro.swift
//  Zerk
//

/// Stands a test double in for what the graph would otherwise build, for the
/// duration of the current scope.
///
/// ```swift
/// #Interject<ApiServicing>(with: MockApi())      // every member of the key
/// #Interject(\.live, with: MockUserService())    // one member
/// ```
///
/// Interjections belong to the scope in force — the `.zerk` trait gives each
/// test its own, so parallel tests never see each other's. Outside a scope this
/// traps rather than leaking, except in a SwiftUI preview, where the process is
/// the scope; see ``ZerkInterjections/processDefault``.
///
/// ## Naming a member
///
/// Every generated member has a point on `Zerk<Key>.Interjection`, named after
/// its signature, so a key path reaches any of them:
///
/// ```swift
/// #Interject(\.live, with: MockLoader())                    // static var live
/// #Interject(\.`seeded(seed: Int)`, with: MockToken())      // static func seeded(seed:)
/// ```
///
/// The key is inferred from the key path, and from `with:` when one name
/// belongs to more than one key. Only a genuine tie needs it spelled —
/// `#Interject<Loading>(\.live, with: …)` — and Swift says so when it happens.
///
/// A blanket interjection always names its key, since there is no key path to
/// infer from. It covers every member, parameterized ones included: arguments
/// are ignored, because a blanket says "this key resolves to this, however it
/// was asked for".
///
/// ## When the double is built
///
/// `with:` is an autoclosure, so the expression runs on every resolution rather
/// than once at registration. `#Interject<K>(with: Mock())` yields a fresh mock
/// each time, matching Zerk's transient default; to hold one and assert on it
/// afterwards, capture it — `#Interject(\.live, with: mock)` — which requires
/// `mock` to be `Sendable`, since a scope is shared across tasks. Built inline,
/// nothing is captured and nothing needs to be `Sendable`.
@freestanding(expression)
public macro Interject<T>(with value: @autoclosure @escaping @Sendable () -> T) = #externalMacro(
    module: "ZerkMacros",
    type: "InterjectMacro"
)

/// The closure form of a blanket interjection, for a double needing more than
/// one statement to build.
@freestanding(expression)
public macro Interject<T>(_ body: @escaping @Sendable () -> T) = #externalMacro(
    module: "ZerkMacros",
    type: "InterjectMacro"
)

/// Stands a double in for one member, named by a key path into
/// ``Zerk/Interjection``.
@freestanding(expression)
public macro Interject<T>(_ keyPath: KeyPath<Zerk<T>.Interjection, Void>,
                          with value: @autoclosure @escaping @Sendable () -> T) = #externalMacro(
    module: "ZerkMacros",
    type: "InterjectMacro"
)

/// The closure form, for one member.
@freestanding(expression)
public macro Interject<T>(_ keyPath: KeyPath<Zerk<T>.Interjection, Void>,
                          _ body: @escaping @Sendable () -> T) = #externalMacro(
    module: "ZerkMacros",
    type: "InterjectMacro"
)
