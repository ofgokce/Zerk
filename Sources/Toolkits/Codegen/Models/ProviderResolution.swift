//
//  ProviderResolution.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

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

    /// `@InjectableProviding(primary: true)` — this *provider* wins among its
    /// own type's providers for the key.
    var isProviderPrimary: Bool { provider.isPrimary }

    var isolation: ProviderIsolation { provider.isolation }

    /// The type a `@Singleton`'s shared storage is declared as.
    ///
    /// The provider's declared return type, falling back to the concrete type
    /// for an initializer. Deliberately *not* the injectable key: one instance
    /// serves every key the type claims, so the storage has to be typed as
    /// something assignable to all of them, and the construction expression is
    /// only known to produce this.
    var singletonStorageTypeName: String {
        provider.returnTypeName ?? typeName
    }
}
