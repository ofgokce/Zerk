//
//  ImportedValueMerger.swift
//  Zerk
//

/// Folds `@ImportedInjectableValue` declarations into the values a parameter can
/// be matched against.
///
/// The counterpart of ``ImportedInjectableMerger``, and the same rule: an import
/// joins the pool that *matches* and never the pool that *emits*. A value's
/// member belongs to the module that declares it, so `InjectableValueRecord`
/// carries the reading expression instead and `GeneratorOutputBuilder` skips it.
///
/// Where the two differ is identity. A key import answers for its key, so two
/// of them collide; a value is matched by key **and name** together, so several
/// of one type are the normal case and only a repeated *name* is a conflict.
struct ImportedValueMerger {

    let records: [ImportedInjectableValueRecord]

    /// - Returns: the values to match against, plus anything wrong with the
    ///   imports themselves.
    func merged(into values: [InjectableValueRecord])
    -> (values: [InjectableValueRecord], diagnostics: [CodegenDiagnostic]) {
        guard !records.isEmpty else {
            return (values, [])
        }

        var diagnostics: [CodegenDiagnostic] = []
        var seen: [String: ImportedInjectableValueRecord] = [:]
        // Accumulated separately rather than appended to `values` as we go: the
        // local-collision check below would otherwise match an import against an
        // earlier import and report the wrong conflict.
        var imported: [InjectableValueRecord] = []

        // Sorted so a repeated name always reports against the later
        // declaration, whatever order the files were read in.
        for record in records.sorted(by: { $0.location < $1.location }) {
            let identity = "\(record.typeKey)|\(record.name)"

            // Matching is by key and name, so a local value of the same name is
            // indistinguishable from the import — and picking either would make
            // resolution depend on a file the reader is not looking at.
            if let local = values.first(where: { $0.typeKey == record.typeKey && $0.name == record.name }) {
                diagnostics.append(CodegenDiagnostic(
                    severity: .error,
                    message: "'\(record.name)' is imported as a '\(record.typeName)' value, but this module already declares one (\(local.location.filePath):\(local.location.line)). Rename the import, or drop the local declaration.",
                    location: record.location
                ))
                continue
            }

            if let first = seen[identity] {
                diagnostics.append(CodegenDiagnostic(
                    severity: .error,
                    message: "'\(record.name)' is imported more than once as a '\(record.typeName)' value (also at \(first.location.filePath):\(first.location.line)). Values are matched by name, so rename one of them.",
                    location: record.location
                ))
                continue
            }

            seen[identity] = record
            imported.append(
                InjectableValueRecord(
                    name: record.name,
                    typeKey: record.typeKey,
                    typeName: record.typeName,
                    keyDisplayName: record.typeName,
                    // Nothing is emitted for an import, so there is no body to
                    // copy and no source in this module to reference.
                    bodyText: nil,
                    location: record.location,
                    isolation: record.isolation,
                    injectionMethod: .referenced,
                    importedExpression: record.expression
                )
            )
        }

        return (values + imported, diagnostics)
    }
}
