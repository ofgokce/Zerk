//
//  ProviderEffects.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

/// The `async`/`throws` effects a provider carries, and the syntax for both
/// declaring and calling something that has them.
///
/// Effects accumulate up a resolution chain: if anything a provider needs is
/// async, the member that builds it becomes async too. That is what `merged`
/// is for — effects only ever widen, never cancel out.
///
/// An isolation *hop* also merges in as `isAsync`, because reaching another
/// actor requires `await` exactly as an async call does.
struct ProviderEffects: Equatable {
    let isAsync: Bool
    let isThrowing: Bool

    static let none = ProviderEffects(isAsync: false, isThrowing: false)

    /// What to write after a signature: `" async throws"` and friends.
    var declarationSuffix: String {
        switch (isAsync, isThrowing) {
        case (false, false):
            return ""
        case (false, true):
            return " throws"
        case (true, false):
            return " async"
        case (true, true):
            return " async throws"
        }
    }

    /// What to write before a call: `"try await "` and friends. Always paired
    /// with `declarationSuffix` — a call site and its declaration must agree.
    var callPrefix: String {
        switch (isAsync, isThrowing) {
        case (false, false):
            return ""
        case (false, true):
            return "try "
        case (true, false):
            return "await "
        case (true, true):
            return "try await "
        }
    }
    
    init(isAsync: Bool, isThrowing: Bool) {
        self.isAsync = isAsync
        self.isThrowing = isThrowing
    }
    
    init(from specifiers: String?) {
        self.init(
            isAsync: specifiers?.contains("async") ?? false,
            isThrowing: specifiers?.contains("throws") ?? false)
    }

    /// Union, never intersection: an effect anywhere in a chain propagates to
    /// everything built on top of it.
    func merged(with other: ProviderEffects) -> ProviderEffects {
        ProviderEffects(
            isAsync: isAsync || other.isAsync,
            isThrowing: isThrowing || other.isThrowing
        )
    }
}
