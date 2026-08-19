//
//  injectable.swift
//  Zerk
//

/// Feeds one of this member's own parameters into the dependencies Zerk
/// resolves for it.
///
/// When a resolved dependency's provider needs arguments, those arguments bubble
/// up and become parameters of the generated member. If the member already
/// declares a parameter that would satisfy one of them, `@injectable` says so —
/// and the single parameter serves both.
///
/// ```swift
/// @Injectable
/// final class Foo {
///     init(value: Value) { ... }
/// }
///
/// final class Bar {
///     init(@injected foo: Foo, @injectable value: Value) { ... }
/// }
///
/// // generated:
/// // extension Bar {
/// //     convenience init(value: Value) {
/// //         self.init(foo: Zerk<Foo>.inject(value: value), value: value)
/// //     }
/// // }
/// ```
///
/// Without it the same `value` would be declared twice — once as Bar's own
/// parameter and once bubbled up for `Foo` — which is reported rather than
/// silently merged, so sharing is always something you wrote down.
///
/// Matched by name *and* type, the same rule that decides whether an
/// `@InjectableValue` satisfies a provider parameter. A parameter whose name
/// differs from the requirement's does not match, and the requirement bubbles up
/// on its own.
///
/// Works for both resolution paths: alongside ``injected`` on any member, and
/// alongside ``autoinjected`` on a provider.
///
/// The wrapper is semantically inert — it performs no resolution and supplies no
/// default. It exists so per-parameter marking is legal Swift, since attached
/// macros cannot be applied to parameters.
@propertyWrapper
public struct injectable<Value> {

    public var wrappedValue: Value

    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }
}

extension injectable: Sendable where Value: Sendable {}
