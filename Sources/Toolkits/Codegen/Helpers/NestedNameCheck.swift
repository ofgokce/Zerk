//
//  NestedNameCheck.swift
//  Zerk
//

/// Refuses a bare type name that Swift resolves to a type nested in the scope
/// it was written in.
///
/// Zerk reads a dependency's spelling where the developer wrote it, inside some
/// type, and re-emits it at **file scope** in the generated file. Swift's lookup
/// is innermost-first, so those two places do not always agree: written inside
/// `LiveFeed`, a bare `Config` means `LiveFeed.Config`, and the same word at
/// file scope means a different type or — more often — nothing at all.
///
/// This is the reason `@Injectable` already refuses a nested type, in the same
/// words: Zerk "builds it from the generated file at file scope, where a nested
/// name does not resolve". A nested type reached as a *dependency* had no such
/// check, and produced a generated file that failed to compile with
/// `cannot find type 'Config' in scope` — pointing at code the developer never
/// wrote — or, where the enclosing name also existed at file scope, silently
/// resolved against the wrong key.
///
/// Qualifying is always available and always works, so the diagnostic asks for
/// it rather than refusing the design.
struct NestedNameCheck {
    let declaredAccessRanks: [String: [DeclaredAccessRecord]]

    /// The type a bare `name` resolves to when written inside `scope`, or `nil`
    /// when file scope answers for it and the two agree.
    ///
    /// Walks outward, innermost frame first, exactly as Swift's lookup does. A
    /// spelling that is already qualified never reaches here — its nominal names
    /// carry the dot — so writing `LiveFeed.Config` is the way out.
    private func nestedMeaning(of name: String, inScope scope: String) -> String? {
        guard !name.contains(".") else { return nil }
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

    private func diagnostic(name: String,
                            qualified: String,
                            location: AttributeLocation) -> CodegenDiagnostic {
        CodegenDiagnostic(
            severity: .error,
            message: "'\(name)' here means '\(qualified)', which Zerk cannot spell: it re-emits this dependency at file scope in the generated file, where the bare name resolves to something else or to nothing. Write '\(qualified)'.",
            location: location
        )
    }

    /// Every bare name in the module that a nested declaration captures.
    ///
    /// Reads the records rather than the syntax, because each already carries
    /// both halves of the question — the scope it was written in and the names
    /// it mentions — and because it has to run once every declaration is known:
    /// a nested type declared below its own use is still the one Swift picks.
    func diagnostics(types: [TypeRecord],
                     markedMembers: [MarkedMemberRecord],
                     injectedUses: [InjectedUseRecord]) -> [CodegenDiagnostic] {
        var found: [CodegenDiagnostic] = []
        // One parameter reaches this through both `initializers` and a provider
        // list, and reporting the same position twice reads as two problems.
        var reported: Set<String> = []
        func report(name: String, qualified: String, at location: AttributeLocation) {
            guard reported.insert("\(location.filePath):\(location.line):\(location.column):\(name)").inserted else {
                return
            }
            found.append(diagnostic(name: name, qualified: qualified, location: location))
        }

        for record in types {
            let providers = record.defaultProviders
                + record.typedProviders.values.flatMap { $0 }
            for parameter in providers.flatMap(\.parameters)
                + record.initializers.flatMap(\.parameters) {
                guard let location = parameter.location else { continue }
                for name in parameter.typeNominalNames.sorted() {
                    if let qualified = nestedMeaning(of: name, inScope: record.name) {
                        report(name: name, qualified: qualified, at: location)
                    }
                }
            }
        }

        for record in markedMembers {
            guard let scope = record.typeName else { continue }
            for marked in record.parameters {
                guard let location = marked.parameter.location else { continue }
                for name in marked.parameter.typeNominalNames.sorted() {
                    if let qualified = nestedMeaning(of: name, inScope: scope) {
                        report(name: name, qualified: qualified, at: location)
                    }
                }
            }
        }

        for use in injectedUses {
            guard let scope = use.enclosingTypeName,
                  let qualified = nestedMeaning(of: use.typeKey, inScope: scope) else {
                continue
            }
            report(name: use.typeKey, qualified: qualified, at: use.location)
        }

        return found
    }
}
