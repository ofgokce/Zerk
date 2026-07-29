//
//  ProviderChoice.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

/// Where a provider came from: an explicit `@Providing` declaration, or the
/// type's sole initializer adopted implicitly.
///
/// The distinction only matters for diagnostics and for naming the generated
/// member. Everything the generator needs — parameters, effects, isolation,
/// source location — is exposed uniformly, so the two cases are otherwise
/// interchangeable.
enum ProviderChoice {
    case explicit(InjectingProvider)
    case implicit(InitializerRecord)

    var parameters: [ParameterRecord] {
        switch self {
        case .explicit(let provider):
            provider.parameters
        case .implicit(let initializer):
            initializer.parameters
        }
    }

    var location: AttributeLocation {
        switch self {
        case .explicit(let provider):
            provider.location
        case .implicit(let initializer):
            initializer.location
        }
    }

    var effects: ProviderEffects {
        switch self {
        case .explicit(let provider):
            provider.effects
        case .implicit(let initializer):
            initializer.effects
        }
    }
    
    var memberNameHint: String? {
        switch self {
        case .explicit(let provider):
            if case .staticFunction(let name) = provider.kind {
                return name
            }
            return nil
        case .implicit:
            return nil
        }
    }

    var isolation: ProviderIsolation {
        switch self {
        case .explicit(let provider):
            provider.isolation
        case .implicit(let initializer):
            initializer.isolation
        }
    }
}
