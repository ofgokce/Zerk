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

    /// The type inside `T?`, `T!` or `Optional<T>`, or `nil` when this is not an
    /// optional.
    ///
    /// `@Injected var service: Service?` injects a `Service` — the optionality
    /// belongs to the property, not to the key. Unwrapping the *syntax* rather
    /// than trimming `Optional<…>` off the canonical string is what lets the key
    /// and its ``typeKeyShape`` be read from one type.
    var unwrappedOptional: TypeSyntax? {
        if let optional = self.as(OptionalTypeSyntax.self) {
            return optional.wrappedType
        }
        if let implicit = self.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return implicit.wrappedType
        }
        if let identifier = self.as(IdentifierTypeSyntax.self),
           identifier.name.text == "Optional",
           let argument = identifier.genericArgumentClause?.arguments.first,
           case .type(let wrapped) = argument.argument {
            return wrapped
        }
        return nil
    }

    /// This key's ``KeyShape`` — its base name and arity with the arguments
    /// holed out — or `nil` when no generic registration could ever match it.
    ///
    /// Derived from the tree, not by taking `normalizedTypeKey` apart, for the
    /// reason that file already gives about sugar: a canonical string looks
    /// decomposable and is not, once `->` and nesting are in play.
    ///
    /// `nil` for everything but a nominal generic application, and that is not a
    /// gap. A registration comes from a type *declaration*, so a pattern is
    /// always `Name<…>` — never sugar, a tuple, a function type, or a
    /// composition. `Cache<String>?` normalizes to `Optional<Cache<String>>`,
    /// whose shape would be `Optional<#0>`; nothing registers that, and missing
    /// it is correct — an optional dependency is genuinely not the thing itself.
    var typeKeyShape: String? {
        Self.shape(of: Syntax(self))
    }

    /// The nominal type's name without its generic arguments — `Box` for
    /// `Box<X, Y>`, `A.Foo` for `A.Foo<Int>`, `URLSession` for `URLSession`.
    ///
    /// `nil` for anything that is not a nominal type, since only a nominal one
    /// has a name to take.
    var nominalBaseName: String? {
        if let someOrAny = self.as(SomeOrAnyTypeSyntax.self) {
            return someOrAny.constraint.nominalBaseName
        }
        if let identifier = self.as(IdentifierTypeSyntax.self) {
            return identifier.name.text
        }
        if let member = self.as(MemberTypeSyntax.self) {
            return "\(member.baseType.normalizedTypeKey).\(member.name.text)"
        }
        return nil
    }

    /// Every nominal type this spelling mentions, at any depth.
    ///
    /// `Cache<String>` reports both `Cache` and `String`; `any Alpha & Beta`
    /// reports both protocols; `(Int) -> Void` reports both; a tuple reports its
    /// elements. A member type reports the whole path *and* its base, since both
    /// have to be visible for the spelling to be legal.
    ///
    /// A **tree walk**, and deliberately not a second pass over the canonical
    /// key string. Taking that string apart is what `typeKeyShape` already warns
    /// against — "a canonical string looks decomposable and is not, once `->`
    /// and nesting are in play" — and a scanner that counted `<` and `>` did in
    /// fact mistake the `>` of a `->` for the end of a generic argument list.
    ///
    /// Used to decide whether a generated member may be `public`, and whether a
    /// type is visible to the generated file. Both questions are about *every*
    /// type in the spelling, not one name extracted from it: a member exposing
    /// `any Alpha & Beta` is only as public as the less public of the two.
    var nominalNames: Set<String> {
        var names: Set<String> = []
        Self.collectNominalNames(in: Syntax(self), into: &names)
        return names
    }

    private static func collectNominalNames(in node: Syntax, into names: inout Set<String>) {
        if let type = node.as(TypeSyntax.self), let name = type.nominalBaseName {
            names.insert(name)
        }
        for child in node.children(viewMode: .sourceAccurate) {
            collectNominalNames(in: child, into: &names)
        }
    }

    /// Which of the generic parameters in `scope` this type mentions, in the
    /// order they appear.
    ///
    /// `scope` is the parameters of the enclosing declarations — for a provider
    /// inside `struct Cache<E>`, that is `["E"]`. So `Serializer<E>` reports
    /// `["E"]`, `Logger` reports nothing, and `Dictionary<E, F>` reports both.
    ///
    /// A **tree walk, never a substring test**, and the distinction is not
    /// academic: `"Encoder"` starts with `"E"`, `"Serializer<Element>"` contains
    /// it, and `Foo.E` is a nested type of `Foo` rather than the parameter. Only
    /// an `IdentifierTypeSyntax` leaf spelled exactly like a parameter *is* that
    /// parameter — which is why the base of `E.Element` counts and the name does
    /// not.
    func mentionedGenericParameters(in scope: Set<String>) -> [String] {
        guard !scope.isEmpty else {
            return []
        }
        var found: [String] = []
        var seen = Set<String>()
        Self.collectIdentifiers(Syntax(self), in: scope, into: &found, seen: &seen)
        return found
    }

    /// Whether the type *is* one of the parameters in `scope`, rather than
    /// merely mentioning one.
    ///
    /// A bare parameter cannot be a key — nothing in the module registers `E` —
    /// so a dependency spelled this way has to be reported rather than matched
    /// against a type that happens to share the name. Canonicalized first, so
    /// the grouping in `(E)` does not hide it.
    func isBareGenericParameter(in scope: Set<String>) -> Bool {
        !scope.isEmpty && scope.contains(normalizedTypeKey)
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
    /// See ``typeKeyShape``. Peels the two wrappers `normalizedTypeKey` also
    /// peels — `any P<T>` and the grouping parentheses in `(P<T>)` — so a shape
    /// and the key it shapes agree on what the type is.
    static func shape(of node: Syntax) -> String? {
        if let someOrAny = node.as(SomeOrAnyTypeSyntax.self) {
            // `some P<T>` is an opaque type, a different thing, and is never
            // reduced away — here or in `canonical`.
            guard someOrAny.someOrAnySpecifier.text == "any" else {
                return nil
            }
            return shape(of: Syntax(someOrAny.constraint))
        }

        if let tuple = node.as(TupleTypeSyntax.self) {
            let elements = Array(tuple.elements)
            guard elements.count == 1,
                  elements[0].firstName == nil,
                  elements[0].ellipsis == nil else {
                return nil
            }
            return shape(of: Syntax(elements[0].type))
        }

        if let identifier = node.as(IdentifierTypeSyntax.self),
           let clause = identifier.genericArgumentClause,
           !clause.arguments.isEmpty {
            return KeyShape.text(base: identifier.name.text, arity: clause.arguments.count)
        }

        if let member = node.as(MemberTypeSyntax.self),
           let clause = member.genericArgumentClause,
           !clause.arguments.isEmpty {
            // The base path is canonicalized the same way the key is, so
            // `A.Foo<Int>`'s shape and key name the same `A.Foo`.
            let base = canonical(Syntax(member.baseType), preservingAny: false)
            return KeyShape.text(base: "\(base).\(member.name.text)",
                                 arity: clause.arguments.count)
        }

        return nil
    }

    /// Pre-order walk collecting every `IdentifierTypeSyntax` leaf whose name is
    /// in `scope`, so the result reads in source order.
    ///
    /// Recursing over *all* children rather than matching node kinds one by one
    /// is what makes this total: a parameter can appear inside a generic
    /// argument, a tuple element, a function parameter or return, an array or
    /// dictionary, a composition, or the base of a member type, and any list of
    /// kinds would eventually miss one.
    static func collectIdentifiers(_ node: Syntax,
                                   in scope: Set<String>,
                                   into found: inout [String],
                                   seen: inout Set<String>) {
        if let identifier = node.as(IdentifierTypeSyntax.self) {
            let name = identifier.name.text
            if scope.contains(name), seen.insert(name).inserted {
                found.append(name)
            }
            // Falls through: `Cache<E>` is an identifier whose arguments still
            // have to be walked.
        }
        for child in node.children(viewMode: .sourceAccurate) {
            collectIdentifiers(child, in: scope, into: &found, seen: &seen)
        }
    }

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

public extension TypeSyntax {
    /// Whether this spelling binds generic arguments anywhere in it.
    ///
    /// `Cache<Int>` does, `Outer.Inner<E>` does, `Cache` does not. Asked of the
    /// tree rather than by looking for a `<`, which is the same reason
    /// ``nominalNames`` is a walk: a question about syntax answered against
    /// rendered text is a question answered about the wrong thing.
    var containsGenericArguments: Bool {
        Self.bindsArguments(Syntax(self))
    }

    private static func bindsArguments(_ node: Syntax) -> Bool {
        if node.is(GenericArgumentClauseSyntax.self) {
            return true
        }
        return node.children(viewMode: .sourceAccurate).contains(where: bindsArguments)
    }
}
