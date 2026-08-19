//
//  MemberNamingRefusal.swift
//  Zerk
//

/// Messages about the arguments that name a generated member — `typeNamed:`
/// and `name:`.
///
/// Shared twice over. Each is raised by the macro, against the declaration, so
/// it shows up in the editor, and again by the build plugin, which reads the
/// same source independently. And the same mistakes are possible on
/// `@Injectable` and on `@InjectableProviding`, which is why the attribute is a
/// parameter rather than part of the sentence.
public enum MemberNamingRefusal {

    /// `typeNamed:` given anything but a literal. Zerk reads syntax and never
    /// evaluates it, so a constant or a flag has no readable value.
    public static func nonLiteralTypeNamed(attribute: String) -> String {
        "\(attribute)(typeNamed:) requires a 'true' or 'false' literal. Zerk reads this from source and cannot evaluate an expression."
    }

    /// `name:` given anything but a string literal. Interpolation counts:
    /// `"\(prefix)Session"` has segments Zerk cannot resolve.
    public static func nonLiteralName(attribute: String) -> String {
        "\(attribute)(name:) requires a string literal. Zerk reads this from source and cannot evaluate an expression or an interpolation."
    }

    /// Both arguments at once. They are alternatives, and honouring one would
    /// silently discard the other.
    public static func conflictingNames(attribute: String, name: String) -> String {
        "\(attribute) states both 'typeNamed: true' and 'name: \"\(name)\"'. They name the same member two ways — keep one."
    }

    /// `typeNamed:` where the type produced has no name to take — `[String]`,
    /// `(Int, String)`, a function type. Only a named type can lend one.
    public static func typeNamedNeedsNamedType(attribute: String, type: String) -> String {
        "\(attribute)(typeNamed:) takes the member's name from the type produced, and '\(type)' has none to lend — it is not a named type. Write 'name:' instead."
    }

    /// `typeNamed:` on an initializer.
    ///
    /// `typeNamed:` names the member after the type the provider *returns*, and
    /// an initializer returns its own type — which is what its member is named
    /// after already. So the argument could only ever be a no-op, and asking for
    /// it means something else was meant.
    public static let typeNamedOnInitializer =
        "@InjectableProviding(typeNamed:) does not apply to an initializer: it can only produce its own type, so its member is named after that type already. Write 'name:' to call it something else."
}
