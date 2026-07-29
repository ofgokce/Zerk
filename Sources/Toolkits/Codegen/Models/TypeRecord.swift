//
//  TypeRecord.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

/// Everything `SourceCollector` learned about one type declaration.
///
/// A type can be injectable under several keys at once (`@Injectable<A>`
/// `@Injectable<B>`), so keyed facts are dictionaries. The provider lists keep
/// duplicates deliberately — reporting "multiple providers for X" requires
/// seeing more than one.
struct TypeRecord {
    let name: String
    let injectableKeys: [String: AttributeLocation]
    let sharedKeys: [String: AttributeLocation]
    let primaryKeys: [String: AttributeLocation]
    let defaultProviders: [InjectingProvider]
    let typedProviders: [String: [InjectingProvider]]
    let initializers: [InitializerRecord]
    let isSingleton: Bool
    var isolation: ProviderIsolation = .nonisolated
}
