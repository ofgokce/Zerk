//
//  InjectionScopeRecord.swift
//  Zerk
//

/// The scope named by `@Scoped(.session)`, as the plugin understands it.
///
/// Zerk reads source and never evaluates it, so the plugin never has an
/// `InjectionScope` value — only the token that names one. That is enough for
/// both jobs it has:
///
/// - **echoing.** The generated storage says `ZerkScopedBox<T>(scope: .session)`,
///   which resolves in the generated file exactly as it did at the attribute.
///   Zerk never constructs a scope from a string, so the runtime identity is
///   whatever the developer's own declaration produces and the two can never
///   drift apart.
/// - **comparing.** The staleness checks — a `@Singleton` capturing a scoped
///   instance, a scope capturing a different one — need to know whether two
///   attributes named the same scope. The member name answers that.
///
/// The leading-dot form is required rather than merely conventional, and this is
/// why: `.session` is a token whose whole meaning is the member it names, so
/// both jobs are exact. `MyScopes.session` would echo fine and compare wrong,
/// and an arbitrary expression would do neither.
struct InjectionScopeRecord: Equatable {

    /// The member name — `session` for `@Scoped(.session)`. The scope's identity
    /// as far as the plugin is concerned.
    let identity: String

    /// How the scope is written back out into the generated file.
    var expression: String {
        ".\(identity)"
    }
}
