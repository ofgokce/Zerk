//
//  InjectableValueRefusal.swift
//  Zerk
//

/// Messages for declarations `@InjectableValue` cannot register.
///
/// Shared because each is raised twice — once by the macro, against the
/// declaration, so it shows up in the editor, and once by the build plugin,
/// which reads the same source independently.
public enum InjectableValueRefusal {

    /// `@InjectableValue` on a function.
    ///
    /// A value is **read** from a declaration and matched by key *and* name; it
    /// never wins its key's `inject()`, and `primary:` means nothing to it. A
    /// function taking arguments is not that shape — it is something the graph
    /// *builds*, which is what `@Injectable` on a global or `static` func
    /// registers, with the declaration as its provider.
    ///
    /// The two differ in what a consumer gets. A value answers a parameter that
    /// matches its key and its name. A registered type answers every request
    /// for that key, through `inject()` like any other.
    public static let functionTarget =
        "@InjectableValue cannot be applied to a function. A value is read from a declaration and matched by key and name, while a function with parameters is something the graph builds — write '@Injectable' on it instead, which registers the type it returns with the function as its provider. For a value that takes no arguments, use a property."
}
