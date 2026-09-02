//
//  NestedNameResolver.swift
//  Zerk
//

/// Reads a bare type name the way Swift does — innermost scope first — and
/// rewrites it to the spelling the generated file can use.
///
/// Zerk takes a dependency's spelling from where the developer wrote it, inside
/// some type, and re-emits it at **file scope**. Swift's lookup is
/// innermost-first, so the two places disagree for anything nested: written
/// inside `LiveFeed`, a bare `Config` means `LiveFeed.Config`, and that same
/// word at file scope means a different type or nothing at all. Emitting it
/// unchanged produced `cannot find type 'Config' in scope` against generated
/// code, or — where the name also existed at file scope — matched the wrong key
/// and ran the effect and conditional-compilation checks against the wrong
/// provider.
///
/// So the name is qualified rather than refused. `LiveFeed.Config` names the
/// same type from anywhere in the module, which makes it both the spelling the
/// generated file needs and the one the developer could have written.
///
/// Applied to the collected records rather than to syntax, because each record
/// already carries both halves of the question — the scope it was written in
/// and the names it mentions — and because it has to run once the whole module
/// is known: a nested type declared *below* its own use is still the one Swift
/// picks.
struct NestedNameResolver {
    let declaredAccessRanks: [String: [DeclaredAccessRecord]]

    /// The type a bare `name` resolves to when written inside `scope`, or `nil`
    /// when file scope answers for it and the two agree.
    ///
    /// Walks outward, innermost frame first, exactly as Swift's lookup does.
    func nestedMeaning(of name: String, inScope scope: String) -> String? {
        guard !declaredAccessRanks.isEmpty, !scope.isEmpty else { return nil }
        var frames = scope.split(separator: ".").map(String.init)
        while !frames.isEmpty {
            let qualified = (frames + [name]).joined(separator: ".")
            if declaredAccessRanks[qualified] != nil {
                return qualified
            }
            frames.removeLast()
        }
        return nil
    }

    /// Every bare name in `text` that `scope` captures, rewritten to its
    /// qualified spelling.
    ///
    /// Scans for the *starts* of type references, as
    /// ``KeyAliases/unqualified(_:modules:clashing:)`` does and for the same
    /// reason: only there does an identifier name a type rather than continue a
    /// dotted path into one. `Config.Key` inside `LiveFeed` becomes
    /// `LiveFeed.Config.Key`, since Swift resolves its base the same way, while
    /// the `Key` after the dot is left alone.
    func qualifying(_ text: String, inScope scope: String) -> String {
        guard !scope.isEmpty, !text.isEmpty else { return text }

        var result = ""
        var index = text.startIndex
        var startsReference = true

        while index < text.endIndex {
            let character = text[index]

            guard character.isZerkIdentifierStart else {
                result.append(character)
                startsReference = character != "."
                index = text.index(after: index)
                continue
            }

            var end = index
            while end < text.endIndex, text[end].isZerkIdentifierContinuation {
                end = text.index(after: end)
            }
            let word = String(text[index..<end])

            if startsReference, let qualified = nestedMeaning(of: word, inScope: scope) {
                result.append(qualified)
            } else {
                result.append(word)
            }
            index = end
            startsReference = false
        }

        return result
    }

    /// One parameter's spellings, qualified together.
    ///
    /// The key and the written name are rewritten as a pair because they answer
    /// for each other: the key is what a provider is matched against, the name
    /// is what the generated file spells, and a parameter whose key moved into a
    /// scope while its spelling stayed behind would resolve and then fail to
    /// compile.
    private func resolving(_ parameter: ParameterRecord,
                           inScope scope: String) -> ParameterRecord {
        var parameter = parameter
        parameter.typeKey = qualifying(parameter.typeKey, inScope: scope)
        parameter.typeName = qualifying(parameter.typeName, inScope: scope)
        parameter.typeNominalNames = Set(
            parameter.typeNominalNames.map { qualifying($0, inScope: scope) })
        return parameter
    }

    func resolved(types: [TypeRecord],
                  markedMembers: [MarkedMemberRecord],
                  injectedUses: [InjectedUseRecord])
    -> (types: [TypeRecord],
        markedMembers: [MarkedMemberRecord],
        injectedUses: [InjectedUseRecord]) {

        let types = types.map { record -> TypeRecord in
            var record = record
            let scope = record.name
            record.defaultProviders = record.defaultProviders.map {
                var provider = $0
                provider.parameters = provider.parameters.map { resolving($0, inScope: scope) }
                return provider
            }
            record.typedProviders = record.typedProviders.mapValues { providers in
                providers.map {
                    var provider = $0
                    provider.parameters = provider.parameters.map { resolving($0, inScope: scope) }
                    return provider
                }
            }
            record.initializers = record.initializers.map {
                var initializer = $0
                initializer.parameters = initializer.parameters.map { resolving($0, inScope: scope) }
                return initializer
            }
            return record
        }

        let markedMembers = markedMembers.map { record -> MarkedMemberRecord in
            guard let scope = record.typeName else { return record }
            var record = record
            record.parameters = record.parameters.map {
                var marked = $0
                marked.parameter = resolving(marked.parameter, inScope: scope)
                return marked
            }
            return record
        }

        // Only the key, never a spelling: `@Injected` expands where it was
        // written, so the macro's own `Zerk<Service>.inject()` already reads in
        // the right scope. What was wrong is the key the *plugin* matched it
        // against when deciding whether the chain is resolvable.
        let injectedUses = injectedUses.map { use -> InjectedUseRecord in
            guard let scope = use.enclosingTypeName else { return use }
            var use = use
            use.typeKey = qualifying(use.typeKey, inScope: scope)
            return use
        }

        return (types, markedMembers, injectedUses)
    }
}
