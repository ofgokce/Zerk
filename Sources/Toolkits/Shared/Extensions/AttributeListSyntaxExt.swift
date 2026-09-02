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
    /// or any attribute whose name ends in `Actor` and reads as a *type*.
    ///
    /// It is a heuristic because Zerk reads syntax, not types: nothing in the
    /// source of `@DataStore` says it is a global actor. A custom actor whose
    /// name does not end in `Actor` is therefore invisible here, which is what
    /// `@Isolated<DataStore>` exists to correct.
    ///
    /// The uppercase requirement is what keeps `@globalActor` out. That
    /// attribute *declares* a global actor rather than applying one, and it ends
    /// in `Actor` — so the canonical spelling
    ///
    /// ```swift
    /// @globalActor
    /// actor DataStore { static let shared = DataStore() }
    /// ```
    ///
    /// was read as "isolated to a global actor named `globalActor`", and then
    /// refused for being an actor. That is a build error on a declaration
    /// carrying no Zerk attribute at all. Applying a global actor always spells
    /// a type, and a type is capitalised; declaring one never is.
    var globalActorName: String? {
        for element in self {
            guard case .attribute(let attribute) = element else {
                continue
            }
            if attribute.name == "MainActor" {
                return attribute.name
            }
            if attribute.name.hasSuffix("Actor"),
               attribute.name != "Actor",
               attribute.name.first?.isUppercase == true {
                return attribute.name
            }
        }
        return nil
    }

    /// The actor named by `@Isolated<A>`, which overrides the heuristic above.
    var isolatedMarkerName: String? {
        attributes(named: "Isolated").first?.genericArgumentKeys.first
    }

    /// Zerk's own property macros, which leave the property needing nothing
    /// from an initializer.
    ///
    /// `@Injected` expands to a peer holding the resolved value, which
    /// initializes the property through `@storageRestrictions`; and
    /// `@InjectedDynamically` expands to a getter, so there is no storage at
    /// all. Either way the compiler's synthesized initializer does not ask for
    /// one, and neither may Zerk's model of it.
    static let storageSatisfyingAttributes: Set<String> = [
        "Injected", "InjectedDynamically"
    ]

    /// Attributes that provably leave a property's storage alone, so seeing one
    /// is no reason to stop inferring an initializer.
    ///
    /// Global actors are handled by ``globalActorName`` rather than listed
    /// here, so there is one definition of "this names a global actor" instead
    /// of two that can drift. They belong in this category on merit: a
    /// global-actor annotation changes neither the synthesized initializer's
    /// parameters nor its isolation — a nonisolated initializer may still
    /// initialize an isolated stored property.
    /// Only names that can actually appear here: `unchecked` belongs to an
    /// inheritance clause (`@unchecked Sendable`) and `@Sendable` to functions
    /// and closures, so listing either would read as a considered case when it
    /// cannot occur.
    static let storageNeutralAttributes: Set<String> = [
        "objc", "nonobjc", "available", "inlinable", "usableFromInline",
        "preconcurrency", "IBOutlet", "IBInspectable",
        "NSCopying", "NSManaged", "Isolated"
    ]

    /// Property wrappers whose memberwise contribution is the *wrapped* value,
    /// so Zerk's reading of the property is already right.
    ///
    /// A wrapper with `init(wrappedValue:)` puts the wrapped type in the
    /// memberwise initializer — `@Bindable var model: SearchModel` takes a
    /// `SearchModel` — which is exactly what reading the annotation gives.
    ///
    /// **Curated and incomplete on purpose.** It cannot be derived: the
    /// declaration lives in another module, and syntax cannot tell a wrapper
    /// with that initializer from one without. `@Environment` is the
    /// counterexample worth remembering — it has no `init(wrappedValue:)`, so it
    /// contributes nothing to the memberwise initializer, and listing it here
    /// would be wrong.
    static let wrappedValueAttributes: Set<String> = [
        "Bindable", "State", "StateObject", "ObservedObject", "Published"
    ]

    /// Whether an attached macro here already gives the property its value.
    var satisfiesItsOwnStorage: Bool {
        contains { element in
            guard case .attribute(let attribute) = element else {
                return false
            }
            return Self.storageSatisfyingAttributes.contains(attribute.name)
        }
    }

    /// The first attribute whose effect on storage Zerk cannot read, or `nil`
    /// when every attribute here is one it can account for.
    ///
    /// A property wrapper and an attached macro are both spelled `@Name`, and
    /// either can change whether a property is stored, whether it is defaulted,
    /// and what type the memberwise initializer asks for. Syntax cannot tell
    /// them from an annotation that does nothing — so anything not accounted
    /// for is reported rather than assumed harmless.
    var unreadableStorageAttribute: String? {
        for element in self {
            guard case .attribute(let attribute) = element else {
                continue
            }
            let name = attribute.name
            if Self.storageSatisfyingAttributes.contains(name)
                || Self.storageNeutralAttributes.contains(name)
                || Self.wrappedValueAttributes.contains(name) {
                continue
            }
            // Reuses the heuristic the isolation reader uses, so a custom global
            // actor is recognised here exactly as it is there.
            if AttributeListSyntax([element]).globalActorName != nil {
                continue
            }
            return name
        }
        return nil
    }
}

public extension AttributeListSyntax {
    /// The first property wrapper here that Zerk knows by name, or `nil`.
    ///
    /// Reads ``wrappedValueAttributes``, so there is one list of "this is a
    /// property wrapper whose wrapped value is what you see" rather than two
    /// that can drift. Curated and incomplete for the reason that list gives —
    /// syntax cannot tell a wrapper from any other `@Name` — so this reports a
    /// wrapper it recognises and stays quiet about one it does not.
    var firstWrappedValueAttributeName: String? {
        for element in self {
            guard case .attribute(let attribute) = element else { continue }
            if Self.wrappedValueAttributes.contains(attribute.name) {
                return attribute.name
            }
        }
        return nil
    }
}
