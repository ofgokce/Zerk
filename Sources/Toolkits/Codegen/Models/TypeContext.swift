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
    /// What kind of declaration this is.
    ///
    /// Read when deciding whether a `#if` inside the body changes how the type
    /// is built: a struct's memberwise initializer is shaped by every stored
    /// property, while a class's `init()` only exists when all of them already
    /// hold a value.
    var kind: MarkedTypeKind? = nil
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
