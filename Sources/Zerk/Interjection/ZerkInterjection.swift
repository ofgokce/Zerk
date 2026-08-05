//
//  ZerkInterjection.swift
//  Zerk
//

public extension Zerk {

    /// Namespace for this key's interjection points.
    ///
    /// Uninhabited on purpose: nothing is ever constructed or read here. The
    /// plugin declares one `Void` property per generated member — named, via a
    /// raw identifier (SE-0451), verbatim after that member's signature — purely
    /// so a key path can name it:
    ///
    /// ```swift
    /// extension Zerk<Foo>.Interjection {
    ///     var bar: Void {}                  // static var bar: Foo
    ///     var `foo(a: A, b: B)`: Void {}    // static func foo(a:b:) -> Foo
    /// }
    /// ```
    ///
    /// Keeping these off `Zerk<T>` itself is what makes the scheme total. Hung
    /// there, the point for an argument-free member would collide with the
    /// member — both would be `static var bar` — and only parameterized members
    /// would have a free name. In here every member gets one, whatever its
    /// shape, and `Zerk<T>`'s own namespace is left alone.
    ///
    /// `Void` rather than `Never`: a getter returning `Never` must call another
    /// never-returning function, so `var bar: Never {}` does not compile.
    enum Interjection {}

    /// This key's identity in ``ZerkInterjections``.
    static var _$interjectionKey: ObjectIdentifier {
        ObjectIdentifier(Zerk<T>.self)
    }

    /// The double standing in for a generated member, or `nil` to build the real
    /// thing. Called from the top of every generated member:
    ///
    /// ```swift
    /// static func foo(a: A, b: B) -> Foo {
    ///     if let interjected = _$interjected(for: \.`foo(a: A, b: B)`) { return interjected }
    ///     return Foo(a: a, b: b)
    /// }
    /// ```
    ///
    /// Returns `T?` rather than a generic `V?` so the call site needs no type
    /// annotation — with a generic result, `_$interjected(…) ?? Live()` lets
    /// Swift solve the result as the *fallback's* type, and every lookup then
    /// fails its cast.
    ///
    /// `@inlinable` so a release build can see the body is `nil` and delete both
    /// the branch and the key-path formation; confirmed in optimized SIL, where
    /// the member reduces to its construction alone. Note this ties the
    /// behaviour to the configuration **Zerk itself** was built with, since `#if`
    /// in an inlinable body resolves at the definition site — which is right for
    /// source distribution, where a debug app builds a debug Zerk.
    @inlinable
    static func _$interjected(for keyPath: KeyPath<Interjection, Void>) -> T? {
        #if DEBUG
        return ZerkInterjections.current.value(for: keyPath, of: _$interjectionKey)
        #else
        return nil
        #endif
    }

    /// Registers a double for one member. The target of `#Interject(\.member)`.
    static func _$interject(_ keyPath: KeyPath<Interjection, Void>,
                            _ body: @escaping @Sendable () -> T) {
        ZerkInterjections.current.interject(keyPath, body)
    }

    /// Registers a double for **every** member of this key. The target of
    /// `#Interject<Key>`.
    ///
    /// Reaches parameterized members too — a blanket says "this key resolves to
    /// this, however it was asked for", so arguments are ignored by design.
    static func _$interject(_ body: @escaping @Sendable () -> T) {
        ZerkInterjections.current.interject(_$interjectionKey, body)
    }
}

/// Registration entry points that do **not** name the key.
///
/// `#Interject(\.live, with: MockLoader())` leaves the key to inference, and a
/// macro only ever sees syntax — it never learns what `T` was solved to, so it
/// cannot expand to `Zerk<Loading>._$interject(…)`. Expanding to these instead
/// hands the same inference problem back to the type checker, which is where it
/// was solved in the first place.
///
/// Not for direct use; write `#Interject` instead.
public func _$zerkInterject<T>(_ keyPath: KeyPath<Zerk<T>.Interjection, Void>,
                               _ body: @escaping @Sendable () -> T) {
    Zerk<T>._$interject(keyPath, body)
}
