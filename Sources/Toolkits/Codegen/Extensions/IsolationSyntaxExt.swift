//
//  IsolationSyntaxExt.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 28.07.2026.
//

import SharedToolkit
import SwiftSyntax

/// What a declaration says about its own isolation, before the ambient default
/// is applied. `.unstated` is the case that makes `ZerkSettings.json`
/// necessary: the plugin cannot tell an ambiently-`@MainActor` declaration from
/// a genuinely nonisolated one by syntax alone.
enum StatedIsolation: Equatable {
    case unstated
    case nonisolated
    case globalActor(String)

    /// Applies `fallback` when the declaration states nothing.
    func resolved(default fallback: ProviderIsolation) -> ProviderIsolation {
        switch self {
        case .unstated:
            return fallback
        case .nonisolated:
            return .nonisolated
        case .globalActor(let name):
            return .globalActor(name)
        }
    }
}

extension AttributeListSyntax {

    /// Isolation stated by attributes alone. `@Isolated<A>` wins over the
    /// `*Actor` attribute heuristic, since it exists to correct it.
    var statedIsolationFromAttributes: StatedIsolation {
        if let marker = isolatedMarkerName {
            return .globalActor(marker)
        }
        if let actor = globalActorName {
            return .globalActor(actor)
        }
        return .unstated
    }
}

/// Combines modifiers and attributes into a single stated isolation.
/// `nonisolated` is checked first because it is the one spelling that is
/// unambiguous and real — it changes what the compiler believes, not just what
/// Zerk infers.
func statedIsolation(modifiers: DeclModifierListSyntax?,
                     attributes: AttributeListSyntax?) -> StatedIsolation {
    if modifiers?.isNonisolated == true {
        return .nonisolated
    }
    return attributes?.statedIsolationFromAttributes ?? .unstated
}
