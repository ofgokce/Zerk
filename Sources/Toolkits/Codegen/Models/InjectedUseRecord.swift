//
//  InjectedUseRecord.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

/// A use of the `@Injected` property macro, recorded so the generator can
/// check the resolution chain behind it.
///
/// `@Injected` expands to a synchronous, non-throwing accessor, so a chain that
/// is async, throwing, or crosses an isolation domain cannot satisfy it — that
/// is reported against this record's location.
struct InjectedUseRecord {
    let typeKey: String
    let macroName: String
    /// True when the attribute passes a single unlabeled expression
    /// (`@Injected(Zerk<T>.custom)`) — resolution is explicit, skip chain checks.
    let hasExplicitExpression: Bool
    let location: AttributeLocation
}
