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
/// The `@Shared`/`@Singleton` flags are per *key*, not per type: a type
/// injectable under two keys can be shared for one of them only.
struct ProviderResolution {
    let typeName: String
    let injectableKey: String
    let provider: ProviderChoice
    /// `@Injectable(primary: true)` — this *type* wins the key when several
    /// types claim it.
    let isTypePrimary: Bool
    let isShared: Bool
    let isSingleton: Bool

    /// `@InjectableProviding(primary: true)` — this *provider* wins among its
    /// own type's providers for the key.
    var isProviderPrimary: Bool { provider.isPrimary }

    var isolation: ProviderIsolation { provider.isolation }
}
