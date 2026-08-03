//
//  ZerkImportMacro.swift
//  Zerk
//

/// Adds `import` statements to the file Zerk generates for this module.
///
/// The generated file imports `Zerk` and nothing else, because the plugin reads
/// syntax and has no idea which module a name came from. That is fine while
/// every type in the graph is declared locally, and breaks as soon as one is
/// not: a provider parameter typed `URL`, a key from another module, an
/// `@Injectable` value of a foreign type — all are emitted into a file that
/// cannot see them.
///
/// ```swift
/// #ZerkImport(module: "Foundation", "CoreLocation")
/// ```
///
/// Write it anywhere in the module; every occurrence is collected and the union
/// is imported, deduplicated and sorted. The expansion is empty — this exists
/// only so the instruction is legal Swift for the plugin to read.
///
/// Module names must be plain string literals. The plugin reads them from
/// source and cannot evaluate a constant or an interpolation.
@freestanding(declaration)
public macro ZerkImport(module: String...) = #externalMacro(
    module: "ZerkMacros",
    type: "ZerkImportMacro"
)
