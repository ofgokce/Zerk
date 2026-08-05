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

    /// A parameter of the *type* that the key erased and no argument recovers.
    ///
    /// Under the type's own key every parameter appears in the return type, so
    /// this only arises from a written key. Swift says the same thing as
    /// `generic parameter 'Y' is not used in function signature`; this says it
    /// at the declaration, with both ways out.
    public static func unboundKeyParameters(on name: String,
                                            key: String,
                                            provider: String?,
                                            parameters: [String]) -> String {
        let one = parameters.count == 1
        return "@Injectable<\(key)> erases \(list(parameters)) from '\(name)', and \(describe(provider)) does not take \(one ? "it" : "them") as \(one ? "an argument" : "arguments") — so nothing can infer \(one ? "it" : "them") at the call site. Accept \(list(parameters)) as \(one ? "a parameter" : "parameters"), or drop the key so '\(name)' registers under itself."
    }

    /// A parameter the *provider* declared that nothing in its signature
    /// mentions.
    ///
    /// Never recoverable from the key, whatever the key is: the key describes
    /// the type, and this parameter belongs to the member. An argument is the
    /// only place it could come from.
    public static func unboundProviderParameters(on name: String,
                                                 provider: String?,
                                                 parameters: [String]) -> String {
        let one = parameters.count == 1
        let member = provider.map { "'\($0)'" } ?? "the initializer"
        return "'\(name)': \(member) declares \(list(parameters)), which \(one ? "does" : "do") not appear in its parameters — so nothing at the call site can infer \(one ? "it" : "them"). Take \(list(parameters)) as \(one ? "a parameter" : "parameters"), or drop \(one ? "it" : "them") from the declaration."
    }

    /// `'live'`, or `the initializer` when the provider has no name of its own.
    static func describe(_ provider: String?) -> String {
        provider.map { "'\($0)'" } ?? "the initializer"
    }

    /// `parameterized: true` says "apply my parameters to the key". Only a
    /// generic type has any.
    public static func parameterizedNonGeneric(type name: String) -> String {
        "@Injectable(parameterized: true) applies '\(name)'s own generic parameters to the key, and '\(name)' has none. Drop the argument."
    }

    /// The key has to be written, and written as an existential: `any P<X, Y>`
    /// is the only legal spelling, and Zerk never *adds* `any` — it cannot tell
    /// a protocol from a class, and `any` on a class is a compile error.
    public static func parameterizedNeedsExistentialKey(type name: String, key: String?) -> String {
        guard let key else {
            return "@Injectable(parameterized: true) on '\(name)' needs the protocol to parameterize: write '@Injectable<any P>(parameterized: true)'."
        }
        return "@Injectable<\(key)>(parameterized: true) on '\(name)' needs an existential key. Write 'any \(key)' — a parameterized protocol type is only spelled with 'any', and Zerk never adds it, since it cannot tell a protocol from a class."
    }

    /// The protocol's primary associated types are what the key applies the
    /// parameters to, so there have to be exactly as many.
    public static func parameterizedArityMismatch(type name: String,
                                                 key: String,
                                                 parameters: [String],
                                                 primaryCount: Int) -> String {
        "@Injectable<\(key)>(parameterized: true) applies \(parameters.count) parameter\(parameters.count == 1 ? "" : "s") of '\(name)' — \(list(parameters)) — to a protocol declaring \(primaryCount) primary associated type\(primaryCount == 1 ? "" : "s"). They must match, or the key cannot be spelled."
    }

    public static func singleton(type name: String) -> String {
        "@Singleton cannot be applied to the generic type '\(name)'. A singleton is stored in a static stored property, which Swift does not allow in a generic type — there is nowhere to keep one instance per specialization."
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
