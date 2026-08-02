//
//  autoinjected.swift
//  Zerk
//

/// Marks a provider parameter as one Zerk should resolve.
///
/// A provider's parameters are auto-resolved wherever Zerk can, and anything it
/// cannot resolve becomes a parameter of the generated member for the caller to
/// supply. That is a good default, but it is inferred — add a dependency to the
/// graph and a parameter that used to be caller-supplied silently starts
/// resolving itself.
///
/// Marking any parameter of a provider switches that provider to **explicit
/// mode**: marked parameters are resolved, unmarked ones are always the
/// caller's, and a marked parameter Zerk cannot resolve is a build error at that
/// parameter rather than a silent fallback.
///
/// ```swift
/// @Injectable
/// final class Checkout {
///     @InjectableProviding
///     init(@autoinjected payments: PaymentServicing, orderID: String) { ... }
/// }
///
/// // generated: `payments` resolved, `orderID` left to the caller
/// // static func inject(orderID: String) -> Checkout
/// ```
///
/// With no parameter marked, the provider keeps the inferred behaviour, so this
/// is opt-in per declaration.
///
/// Distinct from ``injected``, which generates an overload of the *enclosing
/// member* for direct construction. They compose: a parameter written
/// `@injected @autoinjected` both drives Zerk's provider resolution and is
/// omitted from the generated direct-construction overload.
///
/// The wrapper is semantically inert — it performs no resolution and supplies no
/// default. It exists so per-parameter marking is legal Swift, since attached
/// macros cannot be applied to parameters; the build plugin does the rest.
/// Because it is an implementation-detail wrapper (SE-0293,
/// `init(wrappedValue:)` only), call sites of the original member are
/// unaffected.
///
/// - Note: The lowercase name is deliberate, matching ``injected`` — it reads
///   like a built-in parameter attribute such as `@escaping`.
@propertyWrapper
public struct autoinjected<Value> {

    public var wrappedValue: Value

    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }
}

extension autoinjected: Sendable where Value: Sendable {}
