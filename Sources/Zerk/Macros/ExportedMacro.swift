//
//  ExportedMacro.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 2.08.2026.
//

/// Makes a key's generated members `public`, so other modules can resolve it.
///
/// Zerk generates `internal` members by default, which keeps a module's graph its
/// own business. `@Exported` opts a key out of that: `inject()` and every named
/// member for it become public, so a consuming module can resolve the primary
/// with `@Injected` or name one specific provider with `@Injected(\.staging)`.
///
/// The key type itself must be `public` — a public member cannot expose an
/// internal type — otherwise the marker is dropped with a warning.
///
/// A `@Singleton`'s shared storage stays private regardless; only its getter is
/// exported.
@attached(peer)
public macro Exported() = #externalMacro(
    module: "ZerkMacros",
    type: "ExportedMacro"
)

/// Exports only the listed keys, for a type injectable under several.
///
/// ```swift
/// @Exported<Storing>
/// @Injectable<Storing, Caching>
/// public final class Store: Storing, Caching { ... }
/// ```
///
/// `Zerk<Storing>`'s members become public; `Zerk<Caching>`'s stay internal. An
/// unparameterized `@Exported` covers every key the type claims.
@attached(peer)
public macro Exported<each T>() = #externalMacro(
    module: "ZerkMacros",
    type: "ExportedMacro"
)
