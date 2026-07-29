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
    /// given an initializer expression, or computed rather than stored. Enums
    /// are excluded outright: they get no synthesized initializer at all.
    var canInferImplicitDefaultInitializer: Bool {
        guard self.as(EnumDeclSyntax.self) == nil else { return false }

        for member in memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  !variable.modifiers.isStatic else { continue }
            
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
    func inferredStructInitializer(in location: AttributeLocation) -> InitializerRecord? {
        var parameters: [ParameterRecord] = []

        for member in memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
            guard !variable.modifiers.isStatic else { continue }

            for binding in variable.bindings {
                if binding.accessorBlock != nil || binding.initializer != nil { continue }

                guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                      let annotation = binding.typeAnnotation else { return nil }

                let name = identifier.identifier.text
                parameters.append(
                    ParameterRecord(
                    label: name,
                    name: name,
                    typeKey: annotation.type.normalizedTypeKey,
                    typeName: annotation.type.trimmedDescription))
            }
        }

        return InitializerRecord(
            parameters: parameters,
            effects: .none,
            location: location)
    }
    
    /// The initializer the compiler would synthesize, if any: memberwise for a
    /// struct, otherwise the no-argument `init()` — and `nil` when neither
    /// applies, meaning the type must declare a provider explicitly.
    func inferredSynthesizedInitializer(in location: AttributeLocation) -> InitializerRecord? {
        if self.as(StructDeclSyntax.self) != nil {
            return inferredStructInitializer(in: location)
        }
        guard canInferImplicitDefaultInitializer else { return nil }
        return InitializerRecord(
            parameters: [],
            effects: .none,
            location: location)
    }
}
