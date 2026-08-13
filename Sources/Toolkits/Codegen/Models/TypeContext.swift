//
//  TypeContext.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

/// One frame of `SourceCollector`'s enclosing-declaration stack.
///
/// Members and nested types inherit isolation from the declaration around them,
/// so the collector pushes a frame on entry and pops it on exit; the top of the
/// stack is the ambient isolation for whatever is being read.
struct TypeContext {
    /// The declared name, unqualified. Nesting is represented by the stack
    /// itself, so consumers join the frames with "." where they need a
    /// qualified name rather than storing one here.
    let name: String
    /// Whether Zerk has to *infer* this type's initializer.
    ///
    /// False once the type declares an initializer or an `@InjectableProviding`
    /// member of its own, because then Zerk builds it from what was written and
    /// never reads the stored properties. That is what decides whether a `#if`
    /// around a stored property can change anything.
    var consultsInference: Bool = true
    /// Isolation of this declaration, used as the fallback for members and
    /// nested declarations that state none of their own.
    var isolation: ProviderIsolation = .nonisolated
    /// Set when this declaration carries `@InjectableValues`, to the method its
    /// members inherit. Deliberately not inherited by nested types — sweeping
    /// stops at the marked declaration's own members.
    var sweptValueMethod: ValueInjectionMethod? = nil
    /// Set when that `@InjectableValues` carries `public: true`, so every member
    /// it sweeps up is exported. A member with its own `@Injectable(public:)`
    /// states its own answer and overrides this.
    var sweptValuesArePublic: Bool = false
    /// This declaration's own generic parameters.
    ///
    /// Unlike ``sweptValueMethod`` these *are* inherited by nested declarations,
    /// because Swift inherits them: `E` is in scope throughout the body of
    /// `struct Cache<E>`, nested types included. The collector unions the whole
    /// stack — see `SourceCollector.genericScope`.
    var genericParameterNames: [String] = []
}
