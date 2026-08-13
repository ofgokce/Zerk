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
    /// Each shape generates a different overload: an initializer delegates via
    /// `self.init(...)`, a method calls through to itself inside an extension,
    /// and a global function calls through to itself at file scope.
    enum MemberKind {
        case initializer
        case method(name: String, isStatic: Bool, returnType: String?)
        /// A top-level `func`. It has no enclosing type, so its overload is a
        /// file-scope function rather than an extension member.
        case globalFunction(name: String, returnType: String?)
    }

    /// Qualified within the module (nested types are dot-joined), or `nil` for a
    /// global function — which has no enclosing type to extend.
    let typeName: String?
    /// `nil` for a global. Only an initializer consults it, and a global is
    /// never one.
    let typeKind: MarkedTypeKind?
    let kind: MemberKind
    /// The `where` clause of the extension this member was declared in, kept
    /// verbatim so the generated extension repeats it.
    ///
    /// Without it the overload lands in an *unconstrained* extension while its
    /// body calls a method that needs the constraint.
    var typeWhereClause: String? = nil
    /// Whether the enclosing type's visibility still has to be checked.
    ///
    /// Set for a member declared in an `extension`, whose own modifiers say
    /// nothing about the type it extends — a `fileprivate` type extended by an
    /// unannotated extension reads as `internal` and the generated file cannot
    /// see it. Checked at emission, because the declaration may be collected
    /// after the extension is.
    var requiresVisibleType: Bool = false
    /// The `#if` the marked declaration sits inside. The generated overload
    /// delegates to it, so it cannot outlive it.
    var condition: CompilationCondition = .unconditional
    var parameters: [MarkedParameter]
    let effects: ProviderEffects
    let isPublic: Bool
    let location: AttributeLocation
    /// Isolation of the member being overloaded. The generated overload lives
    /// in an extension and is pinned, or deliberately left unpinned for actor
    /// instance members, so it can call the original.
    var isolation: MarkedMemberIsolation = .explicit(.nonisolated)
}
