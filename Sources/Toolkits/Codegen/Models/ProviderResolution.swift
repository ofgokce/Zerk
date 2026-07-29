//
//  ProviderResolution.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

/// One `@Injectable` key paired with the provider that won it.
///
/// This is the unit `GeneratorOutputBuilder` emits a `Zerk<Key>` member for.
/// The `@Shared`/`@Primary`/`@Singleton` flags are per *key*, not per type: a
/// type injectable under two keys can be primary for one of them only.
struct ProviderResolution {
    let typeName: String
    let injectableKey: String
    let provider: ProviderChoice
    let isPrimary: Bool
    let isShared: Bool
    let isSingleton: Bool

    var isolation: ProviderIsolation { provider.isolation }
}
