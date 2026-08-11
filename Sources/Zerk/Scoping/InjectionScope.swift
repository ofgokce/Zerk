//
//  InjectionScope.swift
//  Zerk
//

/// A named lifetime that `@Scoped` instances are kept for and `Zerk.reset(_:)`
/// clears.
///
/// A scope is an ordinary value rather than a generic parameter or a case of a
/// closed enum, so an app declares its own in an extension and a library can
/// declare one without either knowing about the other:
///
/// ```swift
/// extension InjectionScope {
///     static let session = InjectionScope("session")
///     static let checkout = InjectionScope("checkout")
/// }
///
/// @Scoped(.session)
/// @Injectable
/// final class SessionCache { … }
///
/// Zerk.reset(.session)   // on logout
/// ```
///
/// ## The name is the identity
///
/// Two `InjectionScope`s are the same scope when their names match, whoever
/// declared them. That is what makes a scope work across modules: a feature
/// module marks `@Scoped(.session)` and the app module calls `Zerk.reset(.session)`
/// without either holding a reference to the other's storage. The corollary is
/// that the name is a shared namespace — pick one specific enough not to
/// collide with a scope some other module declares.
///
/// ## Why the name is not defaulted from `#function`
///
/// A `#function` default reads well and is wrong for the spelling most people
/// reach for. In a *computed* `static var` it yields the property name, but in a
/// `static let` initializer it yields the enclosing **type** name:
///
/// ```swift
/// static var a: InjectionScope { .init() }   // #function == "a"
/// static let b = InjectionScope()            // #function == "InjectionScope"
/// ```
///
/// So every `static let` scope declared that way would share one name, and
/// `Zerk.reset(.session)` would silently clear `.checkout` too. Writing the name
/// costs one repetition and cannot go quietly wrong.
public struct InjectionScope: Hashable, Sendable, CustomStringConvertible {

    /// This scope's identity. See the type's discussion — equality is by name.
    public let name: String

    public init(_ name: String) {
        self.name = name
    }

    public var description: String {
        name
    }
}
