//
//  InjectableValues.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 2.08.2026.
//

/// Registers every eligible static property of a type as an `@Injectable`
/// value, without annotating each one.
///
/// ```swift
/// @InjectableValues(.referenced)
/// enum AppConstants {
///     static let baseURL: String = "api.example.com"
///     static let retries: Int = 3
/// }
/// ```
///
/// A property is swept up when it is `static`, at least `internal`, and
/// declares an explicit type — Zerk reads syntax, so it cannot infer the type
/// that becomes the injection key. A `private` or `fileprivate` property is
/// skipped, since the generated file could not see it. Anything else in the
/// body — methods, nested types, instance properties — is left alone.
///
/// `public: true` exports every property the sweep picks up, exactly as
/// ``Injectable(public:)`` does for one — the generated `Zerk<String>.baseURL`
/// becomes public so another module can read it.
///
/// An individual property may carry its own `@Injectable(...)` to override the
/// method or the access level chosen here, or ``NonInjectable()`` to opt out
/// entirely. Overriding means stating the argument: `@Injectable(public: false)`
/// keeps a property internal inside a `public: true` sweep, while a bare
/// `@Injectable` says nothing about access and inherits the sweep's answer.
@attached(peer)
public macro InjectableValues(_ method: ValueInjectionMethod = .default,
                              public: Bool = false) = #externalMacro(
    module: "ZerkMacros",
    type: "InjectableValuesMacro"
)
