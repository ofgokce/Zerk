//
//  AttributeListSyntaxExt.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 28.07.2026.
//

import SwiftSyntax

public extension AttributeListSyntax {
    /// Every attribute with this name. Returns all of them because Zerk's
    /// attributes repeat: `@Injectable<A> @Injectable<B>` is two entries.
    func attributes(named name: String) -> [AttributeSyntax] {
        compactMap { element in
            guard case .attribute(let attribute) = element,
                  attribute.name == name else { return nil }
            return attribute
        }
    }

    func firstAttribute(named name: String) -> AttributeSyntax? {
        attributes(named: name).first
    }

    func hasAttribute(named name: String) -> Bool {
        !attributes(named: name).isEmpty
    }

    /// The global actor this attribute list names, by heuristic: `@MainActor`,
    /// or any attribute whose name ends in `Actor`.
    ///
    /// It is a heuristic because Zerk reads syntax, not types: nothing in the
    /// source of `@DataStore` says it is a global actor. A custom actor whose
    /// name does not end in `Actor` is therefore invisible here, which is what
    /// `@Isolated<DataStore>` exists to correct.
    var globalActorName: String? {
        for element in self {
            guard case .attribute(let attribute) = element else {
                continue
            }
            if attribute.name == "MainActor" {
                return attribute.name
            }
            if attribute.name.hasSuffix("Actor"),
               attribute.name != "Actor" {
                return attribute.name
            }
        }
        return nil
    }

    /// The actor named by `@Isolated<A>`, which overrides the heuristic above.
    var isolatedMarkerName: String? {
        attributes(named: "Isolated").first?.genericArgumentKeys.first
    }
}
