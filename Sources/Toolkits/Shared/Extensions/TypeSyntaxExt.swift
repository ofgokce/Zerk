//
//  TypeSyntaxExt.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 28.07.2026.
//

import Foundation
import SwiftSyntax

public extension TypeSyntax {
    /// A type's identity, used to match a dependency against a provider.
    ///
    /// Swift lets one type be written several ways, so comparing spellings would
    /// make `[String]` and `Array<String>` different dependencies even though the
    /// compiler knows they are one. This canonicalizes the spellings that are
    /// *decidable from syntax alone* — Zerk resolves nothing, so anything needing
    /// real type resolution is deliberately left alone (see below).
    ///
    /// | Written | Key |
    /// |---|---|
    /// | `[T]`, `Array<T>` | `Array<T>` |
    /// | `[K: V]`, `Dictionary<K, V>` | `Dictionary<K, V>` |
    /// | `T?`, `T!`, `Optional<T>` | `Optional<T>` |
    /// | `()`, `Void` | `Void` |
    /// | `(T)` | `T` |
    /// | `B & A`, `A & B` | `A & B` (sorted) |
    /// | `P`, `any P` | `P` |
    ///
    /// Canonicalization recurses, so `[String]?` and `Optional<Array<String>>`
    /// are one key.
    ///
    /// **`any` is stripped here but never *added*.** Zerk reads tokens, so it
    /// cannot tell a protocol from a superclass or a struct, and `any` is only
    /// legal on an existential — `any Base` for a class is a compile error. The
    /// spelling a developer wrote is preserved by ``displayTypeKey`` instead.
    ///
    /// Deliberately **not** canonicalized, because it would need type
    /// resolution: module qualification (`Swift.String` vs `String`), nested type
    /// paths, and standard-library aliases (`AnyClass`, `Codable`,
    /// `StringLiteralType`). Deliberately **kept distinct**, because they really
    /// are different types: tuple labels, `throws`/`async`, function-type
    /// attributes like `@Sendable`, `some P` vs `any P`, and metatypes.
    var normalizedTypeKey: String {
        canonicalTypeText(preservingAny: false)
    }

    /// The same canonical form, but with `any` left as the developer wrote it.
    ///
    /// Injectable keys are emitted into the generated file — as
    /// `extension Zerk<Key>` and as member return types — so a key needs a
    /// spelling that is legal Swift, and only the author knows whether their key
    /// is an existential. Matching ignores `any`; emission preserves it.
    var displayTypeKey: String {
        canonicalTypeText(preservingAny: true)
    }
}

private extension TypeSyntax {
    /// Rebuilds the type from its syntax tree in canonical form.
    ///
    /// A tree walk rather than a string rewrite, because sugar nests:
    /// `[String: [Int]?]` has to canonicalize inside out, which no amount of
    /// find-and-replace on the rendered text does correctly.
    ///
    /// Unrecognized types fall through to their whitespace-stripped spelling,
    /// which is what Zerk did for everything before canonicalization existed.
    func canonicalTypeText(preservingAny: Bool) -> String {
        Self.canonical(Syntax(self), preservingAny: preservingAny)
    }

    static func canonical(_ node: Syntax, preservingAny: Bool) -> String {
        func recurse(_ type: TypeSyntax) -> String {
            canonical(Syntax(type), preservingAny: preservingAny)
        }

        if let array = node.as(ArrayTypeSyntax.self) {
            return "Array<\(recurse(array.element))>"
        }

        if let dictionary = node.as(DictionaryTypeSyntax.self) {
            return "Dictionary<\(recurse(dictionary.key)), \(recurse(dictionary.value))>"
        }

        if let optional = node.as(OptionalTypeSyntax.self) {
            return "Optional<\(recurse(optional.wrappedType))>"
        }

        // `T!` is not a distinct type — since SE-0054 the implicit unwrapping is
        // a property of the *declaration*, and the type is plain `Optional<T>`.
        if let implicitlyUnwrapped = node.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return "Optional<\(recurse(implicitlyUnwrapped.wrappedType))>"
        }

        if let someOrAny = node.as(SomeOrAnyTypeSyntax.self) {
            let specifier = someOrAny.someOrAnySpecifier.text
            // `some P` is an opaque type, a different thing entirely, so it is
            // never reduced away.
            guard specifier == "any" else {
                return "\(specifier) \(recurse(someOrAny.constraint))"
            }
            return preservingAny
                ? "any \(recurse(someOrAny.constraint))"
                : recurse(someOrAny.constraint)
        }

        if let composition = node.as(CompositionTypeSyntax.self) {
            // Composition is an unordered set — `A & B` and `B & A` are one type
            // — so the elements are sorted to give it a stable spelling. Safe
            // even with a class constraint: `Base & P` and `P & Base` agree too.
            return composition.elements
                .map { recurse($0.type) }
                .sorted()
                .joined(separator: " & ")
        }

        if let tuple = node.as(TupleTypeSyntax.self) {
            let elements = Array(tuple.elements)

            // `()` is spelled `Void` in the standard library.
            if elements.isEmpty {
                return "Void"
            }

            // `(T)` is just `T` — parentheses around a single unlabeled element
            // are grouping, not a one-element tuple (Swift has no such thing).
            if elements.count == 1,
               elements[0].firstName == nil,
               elements[0].ellipsis == nil {
                return recurse(elements[0].type)
            }

            // Labels stay: `(x: Int, y: Int)` and `(Int, Int)` are different
            // types.
            let parts = elements.map { element -> String in
                let label = [element.firstName?.text, element.secondName?.text]
                    .compactMap { $0 }
                    .joined(separator: " ")
                let rendered = recurse(element.type) + (element.ellipsis != nil ? "..." : "")
                return label.isEmpty ? rendered : "\(label): \(rendered)"
            }
            return "(\(parts.joined(separator: ", ")))"
        }

        if let identifier = node.as(IdentifierTypeSyntax.self) {
            // `Void` written as itself, and generic types written explicitly —
            // recursing the arguments is what makes `Array<[Int]>` agree with
            // `Array<Array<Int>>`.
            return identifier.name.text + canonicalArguments(
                identifier.genericArgumentClause,
                preservingAny: preservingAny
            )
        }

        if let member = node.as(MemberTypeSyntax.self) {
            // Module qualification and nested paths are left as written — Zerk
            // cannot tell `A.Foo` from `B.Foo` without resolving them.
            return "\(recurse(member.baseType)).\(member.name.text)" + canonicalArguments(
                member.genericArgumentClause,
                preservingAny: preservingAny
            )
        }

        if let metatype = node.as(MetatypeTypeSyntax.self) {
            return "\(recurse(metatype.baseType)).\(metatype.metatypeSpecifier.text)"
        }

        if let attributed = node.as(AttributedTypeSyntax.self) {
            // `@Sendable`, `inout`, `borrowing` and friends all change the type
            // or the parameter's meaning, so they are carried through verbatim.
            let specifiers = attributed.specifiers.map { $0.trimmedDescription }
            let attributes = attributed.attributes.map { $0.trimmedDescription }
            let prefix = (specifiers + attributes).joined(separator: " ")
            let base = recurse(attributed.baseType)
            return prefix.isEmpty ? base : "\(prefix) \(base)"
        }

        if let function = node.as(FunctionTypeSyntax.self) {
            let parameters = function.parameters
                .map { canonical(Syntax($0.type), preservingAny: preservingAny) }
                .joined(separator: ", ")
            // `throws` and `async` are part of the type; dropping them would
            // merge genuinely different function types.
            let effects = function.effectSpecifiers
                .map { " \($0.trimmedDescription)" } ?? ""
            let returns = canonical(Syntax(function.returnClause.type), preservingAny: preservingAny)
            return "(\(parameters))\(effects) -> \(returns)"
        }

        return node.trimmedDescription.replacingOccurrences(of: " ", with: "")
    }

    /// Renders a generic argument list with every argument canonicalized.
    static func canonicalArguments(_ clause: GenericArgumentClauseSyntax?,
                                   preservingAny: Bool) -> String {
        guard let clause, !clause.arguments.isEmpty else {
            return ""
        }
        let arguments = clause.arguments
            .map { canonical(Syntax($0.argument), preservingAny: preservingAny) }
            .joined(separator: ", ")
        return "<\(arguments)>"
    }
}
