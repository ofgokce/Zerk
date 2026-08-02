//
//  ValueInjectionMethod.swift
//  Zerk
//

/// How an `@Injectable` value reaches the value it injects.
///
/// This only affects values — a `var` or `let` registered as an injectable.
/// Type providers are unaffected.
///
/// ```swift
/// @InjectableValues(.referenced)
/// enum AppConstants {
///     nonisolated(unsafe) static var baseURL: String = "api.example.com"
///     static let retries: Int = 3
/// }
///
/// Zerk<String>.baseURL          // "api.example.com"
/// AppConstants.baseURL = "..."  // Zerk<String>.baseURL follows
/// ```
public enum ValueInjectionMethod {
    /// The declaration's body is copied into the generated member.
    ///
    /// The generated member is self-contained: it re-evaluates that expression
    /// on each resolution and never reads the original declaration, so a later
    /// write to the source is invisible to injection. This is the default, and
    /// the right choice for constants.
    case copied

    /// The generated member reads through to the original declaration.
    ///
    /// Injection sees whatever the source holds at the moment it is resolved,
    /// so a value updated at runtime propagates. When the source is settable,
    /// the generated member is settable too and writes back to it.
    ///
    /// The source must be visible to the generated file, so `private` and
    /// `fileprivate` declarations cannot be referenced.
    case referenced

    /// Defer to `valueInjectionMethod` in `ZerkSettings.json`, which is
    /// `copied` unless set otherwise.
    case `default`
}
