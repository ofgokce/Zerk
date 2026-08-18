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
    /// The scope from `@Scoped(.session)`, or `nil` for the transient default.
    ///
    /// Mutually exclusive with ``isSingleton`` — both are refused together by
    /// `SourceCollector`, since one instance cannot have two lifetimes.
    var scope: InjectionScopeRecord? = nil
    var isolation: ProviderIsolation = .nonisolated
    /// The type's own generic parameters, in declaration order — `["K", "V"]`
    /// for `Store<K, V>`, empty for everything else.
    ///
    /// Names only. The constraints are deliberately not captured: a member
    /// emitted as `where Injectable == Codec<E>` re-derives `E: Codable` from
    /// the same-type requirement, and a specialization violating it still fails
    /// at the call site. Recording them would be work with nothing reading it.
    var genericParameters: [String] = []
    /// Keys this type claims with `@Injectable<any P>(parameterized: true)`, i.e.
    /// the ones spelled `any P<X, Y>` and gated on the availability of
    /// parameterized existentials.
    var parameterizedKeys: [String: AttributeLocation] = [:]
    /// Why Zerk declined to infer an initializer, when it declined for a reason
    /// worth telling the developer.
    ///
    /// Carried rather than diagnosed on the spot so that one mistake produces
    /// one error: not inferring is only a problem if nothing else provides the
    /// type, and that is settled a stage later.
    var initializerInferenceRefusal: String? = nil
    /// The `#if` clauses this declaration sits inside.
    ///
    /// Everything generated for the type is emitted under the same guard, and
    /// registrations in different clauses of one `#if` never compete for a key.
    /// See ``CompilationCondition``.
    /// Whether the declaration's own inheritance clause names `Sendable`, with
    /// or without `@unchecked`.
    ///
    /// Read to decide whether a `@Singleton`'s storage slot needs
    /// `nonisolated(unsafe)`. It is *not* a claim that the type is Sendable —
    /// syntax cannot settle that, and a conformance added in an extension or
    /// inherited through a protocol is invisible here. It is the narrower fact
    /// the emitter actually needs: whether the compiler will already know, in
    /// which case the annotation is not merely redundant but diagnosed —
    /// "'nonisolated(unsafe)' is unnecessary for a constant with 'Sendable'
    /// type", which is a build failure under `-warnings-as-errors` in a file
    /// the developer cannot edit.
    ///
    /// Erring towards `false` costs the old behaviour and nothing more; erring
    /// towards `true` would drop an annotation Swift 6 requires. So only what is
    /// written on the declaration counts.
    var declaresSendable: Bool = false
    var condition: CompilationCondition = .unconditional

    /// Whether one instance of this type is kept and handed out repeatedly,
    /// however long it is kept for.
    ///
    /// `@Singleton` and `@Scoped` differ only in when the instance is dropped,
    /// and every rule that follows from *sharing* holds for both: one storage
    /// per type rather than per key, one provider across every key, no caller
    /// arguments, and no generic specialization to store per.
    var isShared: Bool {
        isSingleton || scope != nil
    }

    /// Which of the two a diagnostic should name.
    var sharingAttributeName: String {
        isSingleton ? "@Singleton" : "@Scoped"
    }
}
