//
//  GenericGate.swift
//  Zerk
//

import SharedToolkit

/// Drops the generic registrations Zerk still cannot emit, and says why.
///
/// Only one thing is refused here now: **`@Singleton`**. Its storage is a static
/// stored property, which Swift does not allow in a generic type, so there is
/// nowhere to keep one instance per specialization. That is permanent, and it is
/// decidable from the type alone — which is why it lives at this stage.
///
/// The other generic refusal is not: whether a provider can bind the type's
/// parameters depends on *that provider's* signature, so it is settled per
/// resolution in `ProviderResolver`.
///
/// Runs **before** `ProviderResolver`, so a refused type is gone before anything
/// asks which provider backs its key — otherwise a generic type with no provider
/// would collect a second, redundant diagnostic about that.
enum GenericGate {

    /// The types that can be emitted, plus one diagnostic per type that cannot.
    static func admitted(_ types: [TypeRecord]) -> (types: [TypeRecord],
                                                    diagnostics: [CodegenDiagnostic]) {
        var admitted: [TypeRecord] = []
        var diagnostics: [CodegenDiagnostic] = []

        for type in types {
            guard !type.genericParameters.isEmpty else {
                admitted.append(type)
                continue
            }
            guard let location = refusalLocation(for: type) else {
                // No `@Injectable` attribute, so nothing was registered and
                // there is nothing to refuse.
                continue
            }

            if type.isSingleton {
                diagnostics.append(CodegenDiagnostic(
                    severity: .error,
                    message: GenericRefusal.singleton(type: type.name),
                    location: location
                ))
                continue
            }

            admitted.append(type)
        }

        return (admitted, diagnostics)
    }

    /// Where to report the refusal: the earliest `@Injectable` that claimed a
    /// key on this type. Earliest rather than any, so the message lands on the
    /// same line whatever order the keys hash in.
    private static func refusalLocation(for type: TypeRecord) -> AttributeLocation? {
        type.injectableKeys.values.min()
    }
}
