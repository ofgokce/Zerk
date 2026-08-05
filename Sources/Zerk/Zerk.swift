//
//  Zerk.swift
//
//
//  Created by Ömer Faruk Gökce on 14.06.2022.
//

/// The Zerk namespace type. All injection members live in generated
/// `extension Zerk<Key>` blocks produced by the Zerk build plugin; the type
/// itself is intentionally empty.
///
/// The parameter is named `Injectable` rather than `T` because it shadows, for
/// the whole of every generated extension, any module type spelled the same. A
/// developer with their own `struct T` would get `cannot convert value of type
/// 'Foo' to expected argument type 'T'` in a file they did not write. So the
/// name is chosen to be *rare*, not descriptive — which rules out `Key`,
/// `Value` and `Element`, however well they match Zerk's own vocabulary.
public enum Zerk<Injectable> {}
