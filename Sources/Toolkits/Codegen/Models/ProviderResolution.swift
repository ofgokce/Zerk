//
//  ProviderResolution.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

import SharedToolkit

/// One `@Injectable` key paired with one provider that satisfies it.
///
/// This is the unit `GeneratorOutputBuilder` emits a `Zerk<Key>` member for. A
/// key can have several of these — one per provider, across every type that
/// claims it — and exactly one of them is chosen to back `inject()`.
///
/// The export/`@Singleton` flags are per *key*, not per type: a type injectable
/// under two keys can be exported for one of them only.
struct ProviderResolution {
    let typeName: String
    let injectableKey: String
    let provider: ProviderChoice
    /// `@Injectable(primary: true)` — this *type* wins the key when several
    /// types claim it.
    let isTypePrimary: Bool
    /// `@Injectable(public: true)` — this key's generated members are `public`.
    let isExported: Bool
    let isSingleton: Bool
    /// `@Scoped(.session)` — this instance is kept until that scope is reset.
    var scope: InjectionScopeRecord? = nil

    /// Whether this resolution reads a kept instance rather than building one.
    /// See ``TypeRecord/isShared``.
    var isShared: Bool {
        isSingleton || scope != nil
    }

    /// Which attribute a diagnostic about the sharing should name.
    var sharingAttributeName: String {
        isSingleton ? "@Singleton" : "@Scoped"
    }
    /// The registering type's generic parameters, empty for a concrete key.
    ///
    /// These are the *member's* parameters once emitted — `static func cache<E>()
    /// … where Injectable == Cache<E>` — so they have to travel with the
    /// resolution rather than be recovered from the key, which is a shape
    /// (`Cache<#0>`) precisely so it does not carry them.
    ///
    /// A generic type can only ever register under its own key, so the type's
    /// parameters and the key's are the same list. `@Injectable<K>` on a generic
    /// type is refused: the attribute cannot name `E` at all, so a written key
    /// could never bind it.
    var genericParameters: [String] = []
    /// Whether this key is a parameterized existential (`any P<X, Y>`), which
    /// exists only from iOS 16 / macOS 13 and so gates the extension it is
    /// emitted into. See `GeneratorOutputBuilder.parameterizedExistentialAvailability`.
    var isParameterizedExistential: Bool = false

    /// Every generic parameter the emitted member declares: the type's, then
    /// whatever the provider adds.
    ///
    /// A member is one declaration, so it has one list — but the two halves are
    /// bound differently. The type's can come from the return type, when the key
    /// carries them; the provider's own never can, since nothing but its
    /// arguments mentions them. Swift rejects a member shadowing the type's
    /// parameter, so the two halves cannot overlap.
    var memberGenericParameters: [String] {
        genericParameters + provider.genericParameters
    }

    /// Whether the emitted member declares generic parameters at all.
    var memberIsGeneric: Bool { !memberGenericParameters.isEmpty }

    /// Whether the *key* binds those parameters, rather than the member's own
    /// arguments.
    ///
    /// The two modes differ in shape, not just in degree:
    ///
    /// ```swift
    /// // key generic — bound by a same-type requirement, so the extension
    /// // cannot bind it in the header
    /// extension Zerk {
    ///     static func cache<E>() -> Cache<E> where Injectable == Cache<E>
    /// }
    /// // key concrete — an ordinary generic method, parameters inferred from
    /// // the arguments and the result erased into the key
    /// extension Zerk<any Boxable> {
    ///     static func box<X, Y>(_ x: X, _ y: Y) -> any Boxable
    /// }
    /// ```
    ///
    /// Read off the key rather than stored: a generic registration is filed
    /// under its ``KeyShape``, and nothing else ever is.
    var keyIsGeneric: Bool { KeyShape.isShape(injectableKey) }

    /// `@InjectableProviding(primary: true)` — this *provider* wins among its
    /// own type's providers for the key.
    var isProviderPrimary: Bool { provider.isPrimary }

    var isolation: ProviderIsolation { provider.isolation }

    /// The type a `@Singleton`'s or `@Scoped`'s shared storage is declared as.
    ///
    /// The provider's declared return type, falling back to the concrete type
    /// for an initializer. Deliberately *not* the injectable key: one instance
    /// serves every key the type claims, so the storage has to be typed as
    /// something assignable to all of them, and the construction expression is
    /// only known to produce this.
    var sharedStorageTypeName: String {
        provider.returnTypeName ?? typeName
    }
}
