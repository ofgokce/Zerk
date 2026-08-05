//
//  KeyIndex.swift
//  Zerk
//

import SharedToolkit

/// The registrations of a module, looked up by the key a dependency asks for.
///
/// Replaces the plain `[String: ProviderResolution]` that every resolution site
/// used, because one key can now be answered two ways: exactly, by a
/// registration spelled the same, or by *shape*, when a generic registration
/// covers the whole family the key belongs to.
///
/// **Exact wins.** A concrete `Cache<String>` registration beats a generic
/// `Cache<E>` one — not a preference, but agreement with the compiler: given
/// both overloads, Swift itself picks the concrete member at the call site, so
/// resolving to the generic one here would make Zerk's account of the graph
/// disagree with the code it emits.
///
/// With no generic registrations — every module today — `patterns` is empty and
/// this is exactly the dictionary it replaced. That equivalence is what makes it
/// safe to swap in ahead of anything generic actually flowing through.
struct KeyIndex<Value> {

    /// Registrations under a key that is a type.
    private var ground: [String: Value] = [:]
    /// Registrations under a ``KeyShape`` — one entry per generic family.
    private var patterns: [String: Value] = [:]

    init(_ entries: [String: Value] = [:]) {
        for (key, value) in entries {
            if KeyShape.isShape(key) {
                patterns[key] = value
            } else {
                ground[key] = value
            }
        }
    }

    /// The registration answering `key`: the exact one, else the family's.
    ///
    /// The `patterns.isEmpty` guard is not just a fast path — it keeps a module
    /// with no generic registrations from ever computing a shape, so the
    /// behaviour of every existing graph is the dictionary lookup it always was.
    subscript(key: String) -> Value? {
        if let exact = ground[key] {
            return exact
        }
        guard !patterns.isEmpty else {
            return nil
        }
        // A shape is its own shape, so a registration key looked up directly
        // finds itself.
        if KeyShape.isShape(key) {
            return patterns[key]
        }
        return nil
    }

    /// The registration answering a dependency whose shape is already known.
    ///
    /// Callers holding the type's syntax pass the shape they read from it —
    /// see ``TypeSyntax/typeKeyShape``. Nothing derives a shape from key text:
    /// canonical keys look decomposable and are not.
    subscript(key: String, shape shape: String?) -> Value? {
        if let exact = self[key] {
            return exact
        }
        guard let shape, !patterns.isEmpty else {
            return nil
        }
        return patterns[shape]
    }

    /// The registration answering a provider *parameter*.
    ///
    /// Separate from the key subscripts because a parameter can be something no
    /// key ever is: a bare generic parameter. Nothing registers `E`, and looking
    /// it up by name would bind whatever module type happens to be spelled the
    /// same — wrongly, since inside the member `E` is the parameter and shadows
    /// that type. Every resolution site goes through here so the check cannot be
    /// forgotten at one of them.
    subscript(parameter: ParameterRecord) -> Value? {
        guard !parameter.isBareGenericParameter else {
            return nil
        }
        return self[parameter.typeKey, shape: parameter.typeKeyShape]
    }

    var values: [Value] {
        Array(ground.values) + Array(patterns.values)
    }

    var isEmpty: Bool {
        ground.isEmpty && patterns.isEmpty
    }

    /// Every registration with the key it is filed under, so callers that walked
    /// the old dictionary still can.
    var entries: [(key: String, value: Value)] {
        ground.map { (key: $0.key, value: $0.value) }
            + patterns.map { (key: $0.key, value: $0.value) }
    }
}
