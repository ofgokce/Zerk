//
//  noninjected.swift
//  Zerk
//

/// Keeps a provider parameter out of Zerk's automatic resolution.
///
/// By default a provider's parameters are resolved wherever Zerk can. That is
/// usually what you want, but it is inferred: a parameter becomes auto-resolved
/// the moment something in the module happens to satisfy it, without the
/// provider being touched. `@noninjected` says "this one is always the
/// caller's", and keeps saying it as the graph grows.
///
/// ```swift
/// @Injectable
/// final class Checkout {
///     @InjectableProviding
///     init(payments: PaymentServicing, @noninjected retries: Int) { ... }
/// }
///
/// // `retries` stays on the generated member even though an
/// // `@Injectable var retries: Int` exists in the module
/// // static func inject(retries: Int) -> Checkout
/// ```
///
/// The inverse of ``autoinjected``, and the one to reach for when a provider is
/// mostly happy inferring: mark the exceptions rather than every parameter. A
/// provider that marks something `@autoinjected` already excludes everything
/// unmarked, so `@noninjected` is redundant there — it is accepted without
/// complaint, since stating every parameter's intent is a reasonable style.
///
/// Marking one parameter both `@autoinjected` and `@noninjected` is a
/// contradiction and is reported.
///
/// The wrapper is semantically inert — it performs no resolution and supplies no
/// default. It exists so per-parameter marking is legal Swift, since attached
/// macros cannot be applied to parameters.
@propertyWrapper
public struct noninjected<Value> {

    public var wrappedValue: Value

    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }
}

extension noninjected: Sendable where Value: Sendable {}
