//
//  MarkedMemberRecord.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

/// Isolation of a generated overload for a user member carrying `@injected`
/// parameters. This is not identical to provider construction isolation: actor
/// instance methods are actor-isolated, but have no global-actor spelling for
/// Zerk to emit, so the overload inherits that isolation from the extension.
enum MarkedMemberIsolation: Equatable {
    case explicit(ProviderIsolation)
    case actorInstance

    var declarationPrefix: String {
        switch self {
        case .explicit(let isolation):
            return isolation.declarationPrefix
        case .actorInstance:
            return ""
        }
    }

    /// The context used when deciding whether resolving an injected dependency
    /// needs `await`. Actor-instance isolation is not a global actor, so reaching
    /// a global-actor dependency from it crosses a domain.
    var dependencyCallContext: ProviderIsolation {
        switch self {
        case .explicit(let isolation):
            return isolation
        case .actorInstance:
            return .nonisolated
        }
    }
}

/// An initializer or method with at least one `@injected` parameter, and the
/// context needed to generate an overload of it in an extension.
struct MarkedMemberRecord {
    /// Initializers and methods generate different overloads: an initializer
    /// delegates via `self.init(...)`, a method calls through to itself.
    enum MemberKind {
        case initializer
        case method(name: String, isStatic: Bool, returnType: String?)
    }

    /// Qualified within the module (nested types are dot-joined).
    let typeName: String
    let typeKind: MarkedTypeKind
    let kind: MemberKind
    let parameters: [MarkedParameter]
    let effects: ProviderEffects
    let isPublic: Bool
    let location: AttributeLocation
    /// Isolation of the member being overloaded. The generated overload lives
    /// in an extension and is pinned, or deliberately left unpinned for actor
    /// instance members, so it can call the original.
    var isolation: MarkedMemberIsolation = .explicit(.nonisolated)
}
