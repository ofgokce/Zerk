//
//  ScopedMacro.swift
//  Zerk
//

/// Keeps one instance of this injectable for the lifetime of a named scope,
/// rebuilding it after `Zerk.reset(_:)` clears that scope.
///
/// ```swift
/// extension InjectionScope {
///     static let session = InjectionScope("session")
/// }
///
/// @Scoped(.session)
/// @Injectable<Caching>
/// final class SessionCache: Caching { … }
/// ```
///
/// Between `@Singleton` — one instance for the process — and the transient
/// default, where every resolution builds afresh. Everything else behaves as it
/// would without the attribute: the same generated members, the same
/// interjection points, the same `inject()`.
///
/// The argument must be written in leading-dot form. Zerk reads source and never
/// evaluates it, so `.session` is both what it echoes into the generated storage
/// *and* the token it compares scopes by when checking that a longer-lived
/// injectable does not capture a shorter-lived one.
@attached(peer)
public macro Scoped(_ scope: InjectionScope) = #externalMacro(
    module: "ZerkMacros",
    type: "ScopedMacro"
)
