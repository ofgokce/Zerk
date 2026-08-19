//
//  Isolated.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 2.08.2026.
//

/// Tells Zerk which global actor a declaration is isolated to, when the build
/// plugin cannot see it from syntax.
///
/// `@Isolated` is **corrective, not declarative**: it restates what the
/// compiler already believes so that Zerk mirrors the right isolation onto the
/// generated members. It does not change the declaration's actual isolation, so
/// claiming something untrue produces generated code that will not compile.
///
/// Two cases need it:
///
/// ```swift
/// // 1. A custom global actor whose name does not end in "Actor", which Zerk's
/// //    attribute heuristic cannot recognise.
/// @Isolated<DataStore>
/// @DataStore
/// @Injectable<Storing>
/// final class FileStore: Storing { init() {} }
///
/// // 2. Isolation inherited through a conformance, which the plugin cannot
/// //    follow across modules.
/// @Isolated<MainActor>
/// @Injectable<Storing>
/// final class UIStore: Storing, SomeMainActorProtocol { init() {} }
/// ```
///
/// For "this is nonisolated", use Swift's own `nonisolated` keyword — it is
/// real, and Zerk reads it.
@attached(peer)
public macro Isolated<A>() = #externalMacro(
    module: "ZerkMacros",
    type: "IsolatedMacro"
)
