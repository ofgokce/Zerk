//
//  DeclaredAccessRecord.swift
//  Zerk
//

/// The access level a type or protocol declaration was written with, including
/// the compilation condition that makes that declaration visible.
///
/// Several declarations can legitimately share one name when they live in
/// mutually exclusive `#if` branches. Keeping the condition beside the access is
/// what lets emission judge the branch it is currently writing instead of letting
/// whichever branch was visited last win for every configuration.
struct DeclaredAccessRecord: Equatable {
    let access: AccessRank
    let condition: CompilationCondition
}
