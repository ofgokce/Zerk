//
//  DeclGroupSyntaxExt.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

import SharedToolkit
import SwiftSyntax

extension DeclGroupSyntax {

    /// Whether the compiler synthesizes a no-argument `init()` for this type.
    ///
    /// It does when every stored instance property already holds a value —
    /// given an initializer expression, computed rather than stored, or
    /// satisfied by an attached macro. Enums are excluded outright: they get no
    /// synthesized initializer at all.
    var canInferImplicitDefaultInitializer: Bool {
        guard self.as(EnumDeclSyntax.self) == nil else { return false }

        for member in memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  !variable.modifiers.isStatic,
                  !variable.attributes.satisfiesItsOwnStorage else { continue }

            for binding in variable.bindings
            where binding.initializer == nil && binding.accessorBlock == nil {
                return false
            }
        }

        return true
    }
    
    /// The memberwise initializer the compiler synthesizes for a struct,
    /// reduced to the parameters a caller must actually supply.
    ///
    /// Stored properties that already have a value are skipped: the
    /// synthesized initializer defaults them, so Zerk never needs to resolve
    /// one. Returns `nil` if a stored property carries no type annotation,
    /// since its type is only recoverable by evaluating the initializer
    /// expression, which reading syntax cannot do.
    ///
    /// Builds its `ParameterRecord`s by hand rather than through
    /// `parameterRecord(locatedBy:genericScope:)` — a synthesized parameter has
    /// no syntax of its own to locate — so `genericScope` has to be threaded
    /// here separately. Easy to forget precisely because this is the one
    /// provider path that does not go through the parameter funnel.
    func inferredStructInitializer(in location: AttributeLocation,
                                   genericScope: Set<String> = []) -> InitializerRecord? {
        var parameters: [ParameterRecord] = []

        for member in memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
            guard !variable.modifiers.isStatic else { continue }
            // A property an attached macro takes care of is not a memberwise
            // parameter — the macro either computes it or defaults it — so
            // asking a caller for one would name an argument the initializer
            // does not have.
            guard !variable.attributes.satisfiesItsOwnStorage else { continue }

            for binding in variable.bindings {
                if binding.accessorBlock != nil || binding.initializer != nil { continue }

                // Anything Zerk cannot read might do to this property what the
                // attributes above do, and it would find out by emitting a call
                // that does not type-check inside the generated file. Refusing
                // to infer sends it down the "declare a provider" path instead,
                // where the diagnostic names the declaration.
                if variable.attributes.unreadableStorageAttribute != nil { return nil }

                guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                      let annotation = binding.typeAnnotation else { return nil }

                let name = identifier.identifier.text
                parameters.append(
                    ParameterRecord(
                    label: name,
                    name: name,
                    typeKey: annotation.type.normalizedTypeKey,
                    typeName: annotation.type.trimmedDescription,
                    typeKeyShape: annotation.type.typeKeyShape,
                    mentionedGenericParameters: annotation.type.mentionedGenericParameters(in: genericScope),
                    isBareGenericParameter: annotation.type.isBareGenericParameter(in: genericScope),
                    typeNominalNames: annotation.type.nominalNames))
            }
        }

        return InitializerRecord(
            parameters: parameters,
            effects: .none,
            location: location)
    }
    
    /// Whether this type says how it is built, rather than leaving Zerk to
    /// infer it.
    ///
    /// Either an initializer of its own or an `@InjectableProviding` member. A
    /// `#if` inside one that only gates a stored property then changes nothing:
    /// the memberwise initializer is never consulted.
    var declaresItsOwnProvider: Bool {
        memberBlock.members.contains { member in
            if member.decl.is(InitializerDeclSyntax.self) {
                return true
            }
            guard let attributes = member.decl.asProtocol(WithAttributesSyntax.self)?.attributes else {
                return false
            }
            return attributes.hasAttribute(named: "InjectableProviding")
        }
    }

    /// The first stored property whose attributes Zerk cannot read, as
    /// (attribute, property), or `nil` when there is none.
    ///
    /// Only properties that would become *required* parameters count: one that
    /// already has a value is not asked for either way, so an attribute on it
    /// changes nothing Zerk depends on.
    var unreadableStoredProperty: (attribute: String, property: String)? {
        for member in memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  !variable.modifiers.isStatic,
                  let attribute = variable.attributes.unreadableStorageAttribute else {
                continue
            }
            for binding in variable.bindings
            where binding.initializer == nil && binding.accessorBlock == nil {
                let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
                return (attribute, name ?? binding.pattern.trimmedDescription)
            }
        }
        return nil
    }

    /// The initializer the compiler would synthesize, if any: memberwise for a
    /// struct, otherwise the no-argument `init()` — and `nil` when neither
    /// applies, meaning the type must declare a provider explicitly.
    func inferredSynthesizedInitializer(in location: AttributeLocation,
                                        genericScope: Set<String> = []) -> InitializerRecord? {
        if self.as(StructDeclSyntax.self) != nil {
            return inferredStructInitializer(in: location, genericScope: genericScope)
        }
        guard canInferImplicitDefaultInitializer else { return nil }
        return InitializerRecord(
            parameters: [],
            effects: .none,
            location: location)
    }

    /// Whether the declaration's own inheritance clause names `Sendable`.
    ///
    /// `@unchecked Sendable` counts: the compiler treats the type as Sendable
    /// either way, which is the only thing the answer is used for. Read from the
    /// inheritance clause and nowhere else — a conformance declared in an
    /// extension or inherited through a protocol is not visible to syntax, and
    /// guessing at one would drop an annotation Swift 6 requires.
    var declaresSendable: Bool {
        inheritanceClause?.inheritedTypes.contains { inherited in
            inherited.type.nominalNames.contains("Sendable")
        } ?? false
    }
}
