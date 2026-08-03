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
/// The keyed and provider-bearing fields are `var` so `AliasRewriter` can fold
/// them onto their representatives by mutating a copy. Rebuilding the record
/// through the memberwise initializer instead is what dropped `isAutoInjected`
/// from `ParameterRecord` — the initializer only *requires* the fields without
/// defaults, so a defaulted one can be forgotten and still compile.
struct TypeRecord {
    let name: String
    var injectableKeys: [String: AttributeLocation]
    var exportedKeys: [String: AttributeLocation]
    /// Keys this type claims with `@Injectable(primary: true)`, i.e. the ones
    /// whose `inject()` it wins when other types claim them too.
    var primaryKeys: [String: AttributeLocation]
    /// Providers written without a key, which serve every key on the type.
    var defaultProviders: [InjectingProvider]
    /// Providers bound to one key by `@InjectableProviding<Key>`.
    var typedProviders: [String: [InjectingProvider]]
    var initializers: [InitializerRecord]
    let isSingleton: Bool
    var isolation: ProviderIsolation = .nonisolated
}
