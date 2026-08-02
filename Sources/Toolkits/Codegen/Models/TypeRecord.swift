//
//  TypeRecord.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

/// Everything `SourceCollector` learned about one type declaration.
///
/// A type can be injectable under several keys at once (`@Injectable<A>`
/// `@Injectable<B>`), so keyed facts are dictionaries. The provider lists hold
/// every provider, not one per key — several providers for a key is the normal
/// case, and `ProviderResolver` unions the two lists per key.
struct TypeRecord {
    let name: String
    let injectableKeys: [String: AttributeLocation]
    let exportedKeys: [String: AttributeLocation]
    /// Keys this type claims with `@Injectable(primary: true)`, i.e. the ones
    /// whose `inject()` it wins when other types claim them too.
    let primaryKeys: [String: AttributeLocation]
    /// Providers written without a key, which serve every key on the type.
    let defaultProviders: [InjectingProvider]
    /// Providers bound to one key by `@InjectableProviding<Key>`.
    let typedProviders: [String: [InjectingProvider]]
    let initializers: [InitializerRecord]
    let isSingleton: Bool
    var isolation: ProviderIsolation = .nonisolated
}
