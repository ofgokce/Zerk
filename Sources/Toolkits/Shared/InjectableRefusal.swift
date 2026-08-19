//
//  InjectableRefusal.swift
//  Zerk
//

/// Messages for declarations `@Injectable` cannot register.
///
/// Shared because each is raised twice — once by the macro, against the
/// declaration, so it shows up in the editor, and once by the build plugin,
/// which reads the same source independently.
public enum InjectableRefusal {

    /// `@Injectable` on an `extension`.
    ///
    /// Refused rather than supported. An extension is not a declaration: it
    /// states no generic parameters of its own, so `extension Wrapper` cannot
    /// say whether `Wrapper` is generic — and for a type from another module
    /// there is no way to find out, which is exactly the case the form would
    /// exist for. It also has no initializer to adopt implicitly, and a `where`
    /// clause would make its providers conditional on something the key cannot
    /// express.
    ///
    /// A type out of reach is registered by putting the key on a provider type
    /// instead, which says the same thing with none of that ambiguity.
    public static func extensionTarget(extending name: String) -> String {
        "@Injectable cannot be applied to an extension. To register '\(name)' — a type you do not declare — put the key on a type that provides it: '@Injectable<\(name)> enum \(providerName(for: name)) { @InjectableProviding static func live() -> \(name) { … } }'."
    }

    /// A plausible name for the provider type in the suggestion, derived from
    /// the key so the message reads like something a developer would write.
    static func providerName(for name: String) -> String {
        let base = name.prefix { $0.isLetter || $0.isNumber }
        return base.isEmpty ? "Providers" : "\(base)Provider"
    }
}
