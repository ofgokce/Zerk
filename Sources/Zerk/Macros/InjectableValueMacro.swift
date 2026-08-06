//
//  InjectableValueMacro.swift
//  Zerk
//

/// Registers a **value** with the dependency graph.
///
/// The counterpart of ``Injectable()``, and deliberately a separate marker: a
/// type is *built* by a provider, a value is *read* from a declaration, and the
/// two are matched differently. A type is matched by its key alone, so one wins
/// `inject()` for it; a value is matched by key **and name** together, which is
/// what stops two unrelated `String` values from being interchangeable. Nothing
/// about `inject()`, `primary:`, or `@InjectableProviding` applies here.
///
/// On a `var` or `let` the declared type is the key and the declaration supplies
/// the value; `@InjectableValue<Key>` registers it under each listed key
/// instead. A value declared inside a type must be `static`.
///
/// ```swift
/// @InjectableValue
/// var timeout: TimeInterval { 30 }
/// ```
///
/// ## Effects
///
/// A value may be `async`, `throwing`, or both, and the resolution propagates
/// them exactly as an effectful provider's do:
///
/// ```swift
/// @InjectableValue
/// var token: String {
///     get async throws { try await keychain.token() }
/// }
/// ```
///
/// An effectful value is read-only, since Swift has no effectful setter, and it
/// cannot be reached by `@Injected` or a key path — the same limits an effectful
/// provider already carries.
///
/// ## Only a property
///
/// This does not apply to a function. A value is *read* from a declaration and
/// matched by key **and** name; it never wins its key's `inject()`, and
/// `primary:` means nothing to it. Something with parameters is built rather
/// than read — which is what ``Injectable()`` on a global or `static` func
/// registers, with the declaration as its provider and the returned type as a
/// real key:
///
/// ```swift
/// @Injectable(typeNamed: true)
/// func makeGreeting(config: Config, name: String) -> Greeting { … }
///
/// Zerk<Greeting>.inject(name: "Ada")   // `config` resolved, `name` supplied
/// ```
///
/// A function marked `@InjectableValue` is an error naming that replacement,
/// and ``InjectableValues()`` passes functions over in silence.
///
@attached(peer)
public macro InjectableValue() = #externalMacro(
    module: "ZerkMacros",
    type: "InjectableValueMacro"
)

@attached(peer)
public macro InjectableValue<each T>() = #externalMacro(
    module: "ZerkMacros",
    type: "InjectableValueMacro"
)

/// Registers a value and states whether its generated member is `public`.
///
/// See ``Injectable(public:)`` — the rule is the same, except that a value's own
/// declaration may stay internal, since only the key appears in the generated
/// member's signature and the accessor reads the source from its body.
@attached(peer)
public macro InjectableValue(public: Bool) = #externalMacro(
    module: "ZerkMacros",
    type: "InjectableValueMacro"
)

@attached(peer)
public macro InjectableValue<each T>(public: Bool) = #externalMacro(
    module: "ZerkMacros",
    type: "InjectableValueMacro"
)

/// Registers a value and states how the generated member reaches it.
///
/// `method` controls whether the value is copied into the generated member or
/// read through to the original declaration — see ``ValueInjectionMethod``.
@attached(peer)
public macro InjectableValue(_ method: ValueInjectionMethod, public: Bool = false) = #externalMacro(
    module: "ZerkMacros",
    type: "InjectableValueMacro"
)

@attached(peer)
public macro InjectableValue<each T>(_ method: ValueInjectionMethod, public: Bool = false) = #externalMacro(
    module: "ZerkMacros",
    type: "InjectableValueMacro"
)
