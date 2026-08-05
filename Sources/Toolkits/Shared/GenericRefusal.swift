//
//  GenericRefusal.swift
//  Zerk
//

/// The messages Zerk reports when a declaration is generic.
///
/// Shared because each refusal is raised twice — once by the macro, against the
/// declaration, so it shows up in the editor, and once by the build plugin,
/// which reads the same source independently and must not emit a member it
/// cannot spell. Two copies of a sentence drift; one does not.
///
/// A generic type registers today under its bare name, so `@Injectable struct
/// Cache<E>` silently produced `extension Zerk<Cache>` — not valid Swift, and
/// reported against a file the developer never wrote. These say so at the
/// declaration instead.
///
/// ``singleton(type:)`` is permanent: static stored properties are illegal in
/// generic types, so a per-specialization shared instance has nowhere to live.
/// The rest are the current boundary of what the generator can emit and are
/// expected to go away.
public enum GenericRefusal {

    public static func injectableType(named name: String,
                                      parameters: [String]) -> String {
        "'\(name)' is generic, which @Injectable cannot register yet: the generated 'extension Zerk<\(name)>' would leave \(list(parameters)) unbound. Register a concrete specialization behind its own type, or drop the parameter."
    }

    public static func singleton(type name: String) -> String {
        "@Singleton cannot be applied to the generic type '\(name)'. A singleton is stored in a static stored property, which Swift does not allow in a generic type — there is nowhere to keep one instance per specialization."
    }

    public static func providingFunction(named name: String,
                                         parameters: [String]) -> String {
        "@InjectableProviding cannot be applied to the generic function '\(name)': the generated member would name \(list(parameters)), which the key does not bind. Give the factory a concrete return type."
    }

    /// The wording `InjectableValueMacro` already used, kept verbatim so the two
    /// reports of the same mistake read the same.
    public static let injectableValueFunction =
        "@InjectableValue cannot be applied to a generic function. The key is the return type, and Zerk reads syntax so it cannot substitute a type parameter."

    /// `'E'`, `'E' and 'F'`, `'A', 'B' and 'C'` — the parameters named the way a
    /// sentence names them.
    static func list(_ names: [String]) -> String {
        let quoted = names.map { "'\($0)'" }
        guard let last = quoted.last else {
            return "a type parameter"
        }
        guard quoted.count > 1 else {
            return last
        }
        return quoted.dropLast().joined(separator: ", ") + " and " + last
    }
}
