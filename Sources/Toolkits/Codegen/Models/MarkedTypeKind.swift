//
//  MarkedTypeKind.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

/// The kind of type enclosing a member that carries `@injected` parameters.
///
/// Needed because a generated initializer overload has to be spelled
/// `convenience init` in a class and plain `init` everywhere else — a class
/// initializer in an extension may only delegate, while value types and actors
/// have no such distinction.
enum MarkedTypeKind {
    case classKind
    case structKind
    case enumKind
    case actorKind
}
