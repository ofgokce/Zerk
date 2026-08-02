//
//  AliasRewriter.swift
//  Zerk
//

/// Rewrites every collected key to its alias group's representative, once,
/// before resolution runs.
///
/// Rewriting up front rather than aliasing at each lookup is deliberate: keys
/// are compared in a dozen places — provider grouping, value matching, `inject()`
/// election, `@Injected` chains, `@injected` parameters — and a lookup-time
/// approach silently misses whichever one it forgets. After this pass, every
/// existing comparison is already alias-aware.
///
/// Only `typeKey` is rewritten. A parameter's `typeName` is the spelling the
/// developer wrote at that site and stays as written, exactly as it does for
/// canonicalization.
struct AliasRewriter {

    let aliases: KeyAliases

    func rewrite(types: [TypeRecord]) -> [TypeRecord] {
        guard !aliases.isEmpty else { return types }
        return types.map { type in
            TypeRecord(
                name: type.name,
                injectableKeys: rewrite(keyed: type.injectableKeys),
                sharedKeys: rewrite(keyed: type.sharedKeys),
                primaryKeys: rewrite(keyed: type.primaryKeys),
                defaultProviders: type.defaultProviders.map(rewrite(provider:)),
                typedProviders: rewriteProviders(type.typedProviders),
                initializers: type.initializers.map(rewrite(initializer:)),
                isSingleton: type.isSingleton,
                isolation: type.isolation
            )
        }
    }

    func rewrite(values: [InjectableValueRecord]) -> [InjectableValueRecord] {
        guard !aliases.isEmpty else { return values }
        return values.map { value in
            let representative = aliases.representative(for: value.typeKey)
            var rewritten = value
            rewritten.typeKey = representative

            // The emitted spelling has to follow the key. A value declared
            // `var names: Names` keys on `Array<String>` once the alias is
            // known, and emitting `extension Zerk<Names>` around it would put
            // the member on the same specialization under a different name than
            // every other reference to that key.
            if representative != value.typeKey {
                rewritten.keyDisplayName = value.keyDisplayName?.hasPrefix("any ") == true
                    ? "any \(representative)"
                    : representative
            }
            return rewritten
        }
    }

    func rewrite(injectedUses: [InjectedUseRecord]) -> [InjectedUseRecord] {
        guard !aliases.isEmpty else { return injectedUses }
        return injectedUses.map { use in
            var rewritten = use
            rewritten.typeKey = aliases.representative(for: use.typeKey)
            return rewritten
        }
    }

    func rewrite(markedMembers: [MarkedMemberRecord]) -> [MarkedMemberRecord] {
        guard !aliases.isEmpty else { return markedMembers }
        return markedMembers.map { member in
            var rewritten = member
            rewritten.parameters = member.parameters.map { marked in
                var copy = marked
                copy.parameter = rewrite(parameter: marked.parameter)
                return copy
            }
            return rewritten
        }
    }

    /// Folds display spellings onto representatives.
    ///
    /// The representative is the spelling to emit — that is what electing it
    /// meant — so a group's entry is the representative itself, carrying `any`
    /// when any member's spelling had it. Every member of a group denotes the
    /// same type, so if one of them legally takes `any`, the representative does
    /// too.
    func rewrite(keyDisplayNames: [String: String]) -> [String: String] {
        guard !aliases.isEmpty else { return keyDisplayNames }

        var rewritten: [String: String] = [:]
        var needsAny = Set<String>()

        for (key, display) in keyDisplayNames {
            let representative = aliases.representative(for: key)
            if display.hasPrefix("any ") {
                needsAny.insert(representative)
            }
            if key == representative {
                rewritten[representative] = display
            } else if rewritten[representative] == nil {
                rewritten[representative] = representative
            }
        }

        for representative in needsAny where !(rewritten[representative]?.hasPrefix("any ") ?? false) {
            rewritten[representative] = "any \(representative)"
        }

        return rewritten
    }
}

private extension AliasRewriter {

    func rewrite(keyed dictionary: [String: AttributeLocation]) -> [String: AttributeLocation] {
        var rewritten: [String: AttributeLocation] = [:]
        for (key, location) in dictionary {
            // A type claiming both spellings of one key collapses to a single
            // entry; the first location wins, which is the one a diagnostic
            // should point at.
            let representative = aliases.representative(for: key)
            if let existing = rewritten[representative] {
                rewritten[representative] = min(existing, location)
            } else {
                rewritten[representative] = location
            }
        }
        return rewritten
    }

    func rewriteProviders(_ providers: [String: [InjectingProvider]]) -> [String: [InjectingProvider]] {
        var rewritten: [String: [InjectingProvider]] = [:]
        for (key, list) in providers {
            rewritten[aliases.representative(for: key), default: []] += list.map(rewrite(provider:))
        }
        for key in rewritten.keys {
            rewritten[key]?.sort { $0.location < $1.location }
        }
        return rewritten
    }

    func rewrite(provider: InjectingProvider) -> InjectingProvider {
        var rewritten = provider
        rewritten.parameters = provider.parameters.map(rewrite(parameter:))
        return rewritten
    }

    func rewrite(initializer: InitializerRecord) -> InitializerRecord {
        var rewritten = initializer
        rewritten.parameters = initializer.parameters.map(rewrite(parameter:))
        return rewritten
    }

    /// Mutates a copy rather than rebuilding the record: this pass is about the
    /// key and nothing else, and listing the fields again would silently drop
    /// whatever gets added to `ParameterRecord` next.
    func rewrite(parameter: ParameterRecord) -> ParameterRecord {
        var rewritten = parameter
        rewritten.typeKey = aliases.representative(for: parameter.typeKey)
        return rewritten
    }
}
