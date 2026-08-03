//
//  ProviderChoice.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

/// Where a provider came from: an explicit `@InjectableProviding` declaration,
/// or the type's sole initializer adopted implicitly.
///
/// The distinction only matters for diagnostics and for naming the generated
/// member. Everything the generator needs — parameters, effects, isolation,
/// source location — is exposed uniformly, so the two cases are otherwise
/// interchangeable.
enum ProviderChoice {
    case explicit(InjectingProvider)
    case implicit(InitializerRecord)
    /// A key from another module, described by `@ImportedInjectable`. It builds
    /// nothing locally — resolving it is a call into the other module — so it
    /// never becomes a generated member, only a way to satisfy a parameter.
    case imported(ImportedInjectableRecord)
    /// A parametric `@InjectableValue` function. It is a value — matched by key
    /// *and* name, and never the key's primary — but everything about *building*
    /// it is a provider's job, so it travels the provider path to be emitted.
    case value(InjectableValueRecord)

    var parameters: [ParameterRecord] {
        switch self {
        case .explicit(let provider):
            provider.parameters
        case .implicit(let initializer):
            initializer.parameters
        case .imported(let record):
            record.parameters
        case .value(let record):
            record.parameters
        }
    }

    var location: AttributeLocation {
        switch self {
        case .explicit(let provider):
            provider.location
        case .implicit(let initializer):
            initializer.location
        case .imported(let record):
            record.location
        case .value(let record):
            record.location
        }
    }

    var effects: ProviderEffects {
        switch self {
        case .explicit(let provider):
            provider.effects
        case .implicit(let initializer):
            initializer.effects
        case .imported(let record):
            record.effects
        case .value(let record):
            record.effects
        }
    }
    
    var memberNameHint: String? {
        switch self {
        case .explicit(let provider):
            if case .staticFunction(let name) = provider.kind {
                return name
            }
            return nil
        case .value(let record):
            return record.name
        case .implicit, .imported:
            return nil
        }
    }

    var isolation: ProviderIsolation {
        switch self {
        case .explicit(let provider):
            provider.isolation
        case .implicit(let initializer):
            initializer.isolation
        case .imported(let record):
            record.isolation
        case .value(let record):
            record.isolation
        }
    }

    /// The return type as written, or `nil` when the provider is an initializer
    /// and therefore produces the type itself.
    var returnTypeName: String? {
        switch self {
        case .explicit(let provider):
            provider.returnTypeName
        case .implicit:
            nil
        case .imported(let record):
            record.typeName
        case .value(let record):
            record.typeName
        }
    }

    /// The complete expression that resolves this key, or `nil` when it is not
    /// an import and the caller should emit `Zerk<Key>.inject(…)` itself.
    ///
    /// Imports own the whole expression, not just its head, because a body may
    /// have named a property — `Zerk<Session>.staging` — which takes no
    /// parentheses however many parameters were declared.
    func resolutionExpression(arguments: [String]) -> String? {
        switch self {
        case .imported(let record):
            if record.resolvesAsProperty {
                return record.callee
            }
            return arguments.isEmpty
                ? "\(record.callee)()"
                : "\(record.callee)(\(arguments.joined(separator: ", ")))"
        case .value(let record):
            // Named, not `inject()`: a value never wins its key, so the only way
            // to reach it is by the name it was declared under.
            return arguments.isEmpty
                ? "Zerk<\(record.keyText)>.\(record.name)()"
                : "Zerk<\(record.keyText)>.\(record.name)(\(arguments.joined(separator: ", ")))"
        case .explicit, .implicit:
            return nil
        }
    }

    /// An implicit initializer is never marked: it is adopted only when the
    /// type declares no provider at all, so it has nothing to be primary over.
    var isPrimary: Bool {
        switch self {
        case .explicit(let provider):
            provider.isPrimary
        case .implicit, .imported, .value:
            false
        }
    }
}
