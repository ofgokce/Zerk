//
//  ZerkAlias.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 2.08.2026.
//

/// Tells Zerk that a `typealias` names an existing injection key rather than a
/// new one.
///
/// ```swift
/// @ZerkAlias
/// typealias Persisting = Storing
/// ```
///
/// Zerk matches dependencies by the *spelling* of a type, so without this a
/// provider registered as `@Injectable<Storing>` would not satisfy a parameter
/// written `Persisting`. Marking the alias merges the two into one key.
///
/// This matters even when nothing depends on the alias: `Zerk<Storing>` and
/// `Zerk<Persisting>` are the same generic specialization, so registering an
/// injectable under each would emit two `inject()` members on one type — a
/// redeclaration error. Merging the keys is what prevents that.
///
/// Generic typealiases are not supported: they describe a family of types, and
/// substituting the parameters would need real type resolution, which the build
/// plugin deliberately does not do. Alias a concrete instantiation instead.
@attached(peer)
public macro ZerkAlias() = #externalMacro(
    module: "ZerkMacros",
    type: "ZerkAliasMacro"
)

/// Registers types as interchangeable when the `typealias` is not declared in
/// this target — in another module, say, where `@ZerkAlias` cannot be attached.
///
/// ```swift
/// #ZerkAlias<Storing, Persisting, Caching>
/// ```
///
/// Every listed type is treated as the same injection key. The expansion is a
/// private, never-called function that pairs the types through a generic
/// same-type parameter, so *the compiler* verifies the claim: listing types that
/// are not actually interchangeable is a build error at the `#ZerkAlias` line
/// rather than a mismatch discovered later. The check is invariant, so a
/// subclass and its superclass are correctly rejected.
// No `names:` clause: the expansion's only declaration is given a compiler-
// unique name via `makeUniqueName`, which is exempt from being declared — and
// `arbitrary` is rejected outright for a declaration macro at global scope,
// which is exactly where #ZerkAlias is meant to be written.
@freestanding(declaration)
public macro ZerkAlias<each T>() = #externalMacro(
    module: "ZerkMacros",
    type: "ZerkAliasDeclarationMacro"
)
