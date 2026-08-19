//
//  ImportedInjectableMerger.swift
//  Zerk
//

/// Folds `@ImportedInjectable` declarations into the resolutions that back
/// implicit resolution.
///
/// Imports go into `primaryResolutions` but **never** into `resolutions`, and
/// that split is the whole design. `resolutions` is what members are emitted
/// from, and an import builds nothing here — its value comes from another
/// module, so `extension Zerk<Key>` and `inject()` belong over there, not
/// duplicated in this module. `primaryResolutions` is what everything resolved
/// implicitly consults, which is exactly where a foreign key needs to appear.
struct ImportedInjectableMerger {

    let records: [ImportedInjectableRecord]

    /// - Returns: the primaries to resolve against, plus anything wrong with the
    ///   imports themselves.
    func merged(into primaries: [String: ProviderResolution],
                localKeys: Set<String>) -> (primaries: [String: ProviderResolution],
                                            diagnostics: [CodegenDiagnostic]) {
        var primaries = primaries
        var diagnostics: [CodegenDiagnostic] = []
        var seen: [String: ImportedInjectableRecord] = [:]

        for record in records.sorted(by: { $0.location < $1.location }) {
            // A key declared here as well is ambiguous in a way Zerk cannot
            // settle: picking either would make resolution depend on a file the
            // reader is not looking at.
            if localKeys.contains(record.typeKey) {
                diagnostics.append(CodegenDiagnostic(
                    severity: .error,
                    message: "'\(record.typeKey)' is both imported and declared @Injectable in this module. Remove the import, or the local declaration.",
                    location: record.location
                ))
                continue
            }

            if let first = seen[record.typeKey] {
                diagnostics.append(CodegenDiagnostic(
                    severity: .error,
                    message: "'\(record.typeKey)' is imported more than once (also at \(first.location.filePath):\(first.location.line)). Keep the one you meant.",
                    location: record.location
                ))
                continue
            }

            seen[record.typeKey] = record
            primaries[record.typeKey] = ProviderResolution(
                typeName: record.typeName,
                injectableKey: record.typeKey,
                provider: .imported(record),
                isTypePrimary: true,
                isExported: false,
                isSingleton: false
            )
        }

        return (primaries, diagnostics)
    }
}
