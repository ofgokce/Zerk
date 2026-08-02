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
/// An individual property may carry its own `@Injectable(...)` to override the
/// method chosen here, or ``NonInjectable()`` to opt out entirely.
@attached(peer)
public macro InjectableValues(_ method: ValueInjectionMethod = .default) = #externalMacro(
    module: "ZerkMacros",
    type: "InjectableValuesMacro"
)
