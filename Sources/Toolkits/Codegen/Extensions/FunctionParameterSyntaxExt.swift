//
//  FunctionParameterSyntaxExt.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

import SharedToolkit
import SwiftSyntax

extension FunctionParameterSyntax {
    /// Flattens Swift's two-name parameter syntax into a label plus an
    /// internal name.
    ///
    /// `f(label name: T)` writes both; `f(name: T)` writes one, which serves as
    /// both; `f(_ name: T)` suppresses the label entirely, recorded as `nil`.
    ///
    /// `locator` resolves the parameter's own position, so a diagnostic about it
    /// lands on the parameter and not on the enclosing declaration. It is
    /// optional because the synthesized memberwise initializer has parameters
    /// with no source of their own.
    ///
    /// `genericScope` is the enclosing declarations' generic parameters, which
    /// decide whether this parameter's type is one key, a family of keys, or a
    /// bare parameter that is none. Empty for every non-generic type, so the
    /// default keeps existing callers exact.
    func parameterRecord(locatedBy locator: ((Syntax) -> AttributeLocation)? = nil,
                         genericScope: Set<String> = []) -> ParameterRecord {
        let firstName = firstName.text
        let secondName = secondName?.text
        return ParameterRecord(
            label: firstName == "_" ? nil : firstName,
            name: secondName ?? firstName,
            typeKey: type.normalizedTypeKey,
            typeName: type.trimmedDescription,
            isAutoInjected: attributes.hasAttribute(named: "autoinjected"),
            isNonInjected: attributes.hasAttribute(named: "noninjected"),
            feedsDependencies: attributes.hasAttribute(named: "injectable"),
            location: locator.map { $0(Syntax(self)) },
            typeKeyShape: type.typeKeyShape,
            mentionedGenericParameters: type.mentionedGenericParameters(in: genericScope),
            isBareGenericParameter: type.isBareGenericParameter(in: genericScope),
            typeNominalNames: type.nominalNames,
            isInout: type.as(AttributedTypeSyntax.self)?.specifiers.contains {
                $0.as(SimpleTypeSpecifierSyntax.self)?.specifier.tokenKind == .keyword(.inout)
            } ?? false,
            isVariadic: ellipsis != nil,
            defaultText: portableDefaultText)
    }

    /// The default value as written, when re-emitting it elsewhere would mean
    /// the same thing.
    ///
    /// A default argument is evaluated at the *call site*, and Zerk's generated
    /// member is a different call site from the declaration it stands in for. For
    /// almost every expression that changes nothing — a literal, an implicit
    /// member, a call to something visible from both — and where it does not, it
    /// does not compile, loudly, in the generated file.
    ///
    /// A magic literal is the exception, and the only silent one: `#function`
    /// exists precisely to capture where it was written from, so carrying it
    /// into `Zerk<Key>.consumer(…)` would hand the developer a different
    /// answer than their own declaration gives, with nothing to notice. Left
    /// behind rather than reproduced, which puts such a parameter back where it
    /// was before any of this: supplied by the caller.
    ///
    /// Found by walking for the expression rather than by looking for a `#` in
    /// the rendered text. The two are not the same question and the text answer
    /// was wrong in both directions people write: `"issue #1"`, `"#FF0000"` and
    /// `#"a\b"#` are string literals that contain the character and mean the
    /// same thing anywhere, while `String(describing: #function)` is a call that
    /// does not contain one at the top level. A walk gets both.
    var portableDefaultText: String? {
        guard let value = defaultValue?.value else {
            return nil
        }
        guard !Self.mentionsMagicLiteral(Syntax(value)) else {
            return nil
        }
        return value.trimmedDescription
    }

    /// Whether an expression names a magic literal anywhere inside it.
    private static func mentionsMagicLiteral(_ node: Syntax) -> Bool {
        if node.is(MacroExpansionExprSyntax.self) {
            return true
        }
        return node.children(viewMode: .sourceAccurate).contains(where: mentionsMagicLiteral)
    }
}
