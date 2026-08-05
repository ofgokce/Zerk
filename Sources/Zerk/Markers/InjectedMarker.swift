//
//  injected.swift
//  Zerk
//

/// Marks an initializer or method parameter as injectable.
///
/// The Zerk build plugin generates an overload of the enclosing member with
/// every `@injected` parameter omitted and filled via `Zerk<Key>.inject()`:
///
/// ```swift
/// final class Checkout {
///     init(@injected payments: PaymentServicing, orderID: String) { ... }
/// }
///
/// // generated:
/// // extension Checkout {
/// //     convenience init(orderID: String) {
/// //         self.init(payments: Zerk<PaymentServicing>.inject(), orderID: orderID)
/// //     }
/// // }
/// ```
///
/// The wrapper itself is semantically inert: it performs no resolution and
/// cannot supply a default value. It exists so that per-parameter marking is
/// legal Swift (attached macros cannot be applied to parameters); the build
/// plugin does all detection, resolution, and code generation. Because it is
/// an implementation-detail wrapper (SE-0293, `init(wrappedValue:)` only),
/// call sites of the original member are completely unaffected.
///
/// - Note: The lowercase type name is deliberate, breaking the UpperCamelCase
///   convention on purpose: it keeps the attribute visually distinct from the
///   `@Injected` property macro (Swift identifiers are case-sensitive, so the
///   two never collide) and reads like a built-in parameter attribute such as
///   `@escaping`. Use `@Injected` for properties; `@injected` for parameters.
@propertyWrapper
public struct injected<Value> {

    public var wrappedValue: Value

    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }
}

extension injected: Sendable where Value: Sendable {}
