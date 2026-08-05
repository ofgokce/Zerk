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
    /// `var` so the alias pass can fold it onto its group's representative.
    var typeKey: String
    /// The key's ``KeyShape``, so an `@Injected var cache: Cache<String>` can
    /// reach a generic registration. See ``ParameterRecord/typeKeyShape``.
    var typeKeyShape: String? = nil
    let macroName: String
    /// True when the attribute named a member with a key path.
    ///
    /// The chain check below is about the key's *primary*, which such a use does
    /// not go through — so it does not apply. Nothing is lost by skipping it: a
    /// key path can only reach a property, and Swift refuses to form one to an
    /// `async` or `throws` property, so anything reachable this way is already
    /// effect-free.
    var namesMemberDirectly: Bool = false
    let location: AttributeLocation
}
