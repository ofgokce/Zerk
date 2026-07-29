//
//  ValueInjectionMethod.swift
//  Zerk
//

/// How an injectable value reaches the value it injects.
///
/// The codegen's mirror of the public `Zerk.ValueInjectionMethod`, minus its
/// `.default` case: "default" is a question about *where* the method comes
/// from, and it is answered at collection time against `ZerkSettings`. By the
/// time a value is recorded the method is always concrete.
enum ValueInjectionMethod: String, Equatable {
    /// Copy the declaration's body into the generated member, which then never
    /// reads the original.
    case copied
    /// Read through to the original declaration, so runtime updates propagate.
    case referenced
}
