//
//  ProviderIsolation.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 28.07.2026.
//

/// The isolation domain a provider constructs in, resolved at collection time
/// from source syntax plus the ambient default declared in `ZerkSettings.json`.
///
/// Zerk mirrors this onto every generated member ("propagation"): a member's
/// isolation *is* its provider's isolation. Isolation does not merge — there is
/// no join of `MainActor` and `DatabaseActor` — so a dependency in a different
/// domain converts into an `async` effect instead.
enum ProviderIsolation: Equatable {
    /// Construction is callable from any domain. Also used for `actor`
    /// providers: an actor's synchronous initializer is nonisolated at entry
    /// (SE-0327), so construction itself never hops.
    case nonisolated
    /// Construction is isolated to a global actor, e.g. `MainActor`.
    case globalActor(String)

    /// The global actor's name, or `nil` when nonisolated.
    var actorName: String? {
        switch self {
        case .nonisolated:
            return nil
        case .globalActor(let name):
            return name
        }
    }

    var isGlobalActor: Bool {
        actorName != nil
    }

    /// Prefix emitted before a generated declaration so its meaning never
    /// depends on the consumer's `SWIFT_DEFAULT_ACTOR_ISOLATION` setting.
    var declarationPrefix: String {
        switch self {
        case .nonisolated:
            return "nonisolated "
        case .globalActor(let name):
            return "@\(name) "
        }
    }

    /// Whether calling something isolated to `self` from a context isolated to
    /// `context` has to cross an isolation boundary — i.e. requires `await` and
    /// carries a sendability obligation.
    ///
    /// The crossing is asymmetric: nonisolated → isolated is free, isolated →
    /// anywhere else is not.
    func requiresHop(callingFrom context: ProviderIsolation) -> Bool {
        switch self {
        case .nonisolated:
            return false
        case .globalActor(let name):
            return context.actorName != name
        }
    }
}
