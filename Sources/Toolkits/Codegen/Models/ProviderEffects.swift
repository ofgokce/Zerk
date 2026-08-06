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
    /// How the provider throws — see ``Throwing``. Three states rather than a
    /// `Bool` because `rethrows` is neither of the other two, and collapsing it
    /// into `throws` is not free: it forces `try` on a call site that passes a
    /// non-throwing closure, which drags `throws` up the caller's own stack.
    let throwing: Throwing

    /// Whether the provider can throw at all — `rethrows` can, so this is true
    /// for it. What is gated on "can this throw" (`@Injected` refusing a chain,
    /// the companion `var` a key path needs) wants exactly this question.
    var isThrowing: Bool { throwing != .none }

    /// Whether it throws *only* when a closure argument does.
    var isRethrowing: Bool { throwing == .rethrowing }

    /// How a declaration throws, ordered by how much it constrains a caller.
    /// Merging takes the maximum, which is what makes an effect widen rather
    /// than cancel.
    enum Throwing: Int, Comparable, Equatable {
        case none = 0
        /// `rethrows`.
        case rethrowing = 1
        /// `throws`, or a typed `throws(E)`.
        ///
        /// A typed throw widens to an untyped one. The generated member would
        /// have to restate `E`, and the moment two providers in a chain name
        /// different error types there is no single `E` left to restate — so the
        /// member says `throws` and the concrete type is the developer's to
        /// catch. `throws(Never)` is not special-cased; it is a spelling of
        /// "cannot throw" that Zerk reads as throwing, which costs a `try` the
        /// compiler then reports as unnecessary.
        case throwing = 2

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    static let none = ProviderEffects(isAsync: false, throwing: .none)

    /// What to write after a signature: `" async throws"` and friends.
    var declarationSuffix: String {
        let asyncPart = isAsync ? " async" : ""
        switch throwing {
        case .none:
            return asyncPart
        case .rethrowing:
            return "\(asyncPart) rethrows"
        case .throwing:
            return "\(asyncPart) throws"
        }
    }

    /// What to write before a call: `"try await "` and friends. Always paired
    /// with `declarationSuffix` — a call site and its declaration must agree.
    ///
    /// `rethrows` takes `try` like any throwing call; whether it *does* throw is
    /// the compiler's to work out from the argument.
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

    init(isAsync: Bool, throwing: Throwing) {
        self.isAsync = isAsync
        self.throwing = throwing
    }

    init(isAsync: Bool, isThrowing: Bool) {
        self.init(isAsync: isAsync, throwing: isThrowing ? .throwing : .none)
    }

    /// Reads an effect clause as written.
    ///
    /// Token-wise rather than by substring: `"rethrows".contains("throws")` is
    /// true, so a substring test answers "throws" for a `rethrows` declaration
    /// by accident rather than by decision. `throws(MyError)` is a `throws`
    /// token with a type argument, and widens.
    init(from specifiers: String?) {
        guard let specifiers else {
            self.init(isAsync: false, throwing: .none)
            return
        }
        // Split on anything that cannot appear in a keyword, so `throws(E)`
        // yields a bare `throws` token and the error type falls out.
        let tokens = specifiers.split(whereSeparator: { !$0.isLetter })
        self.init(
            isAsync: tokens.contains("async"),
            throwing: tokens.contains("rethrows") ? .rethrowing
                : tokens.contains("throws") ? .throwing
                : .none
        )
    }

    /// Union, never intersection: an effect anywhere in a chain propagates to
    /// everything built on top of it.
    ///
    /// `rethrows` merged with a real `throws` is `throws` — once something in
    /// the chain throws unconditionally, the member does too, whatever its own
    /// closure arguments do.
    func merged(with other: ProviderEffects) -> ProviderEffects {
        ProviderEffects(
            isAsync: isAsync || other.isAsync,
            throwing: max(throwing, other.throwing)
        )
    }

    /// `rethrows` narrowed to what the emitted signature can actually carry.
    ///
    /// Swift requires a `rethrows` function to have a throwing function
    /// parameter to rethrow *from*. A provider always has one — that is what
    /// made it `rethrows` — but the member Zerk emits is not the provider: a
    /// parameter can be resolved away into `inject()`, and `inject()` itself may
    /// take none at all. Where the parameter did not survive, the member widens
    /// to `throws`, which is always legal.
    func resolved(forParameters parameters: [ParameterRecord]) -> ProviderEffects {
        guard throwing == .rethrowing,
              !parameters.contains(where: \.isThrowingFunctionType) else {
            return self
        }
        return ProviderEffects(isAsync: isAsync, throwing: .throwing)
    }
}

extension ParameterRecord {
    /// Whether this parameter is a throwing function type, i.e. something a
    /// `rethrows` signature can rethrow from.
    ///
    /// Read from the type as written, because that is all Zerk has. The test is
    /// deliberately narrow: a `throws` token to the left of the arrow. Answering
    /// "no" for something that would in fact have worked only widens the member
    /// to `throws`, which compiles; answering "yes" wrongly would emit a
    /// `rethrows` Swift rejects.
    var isThrowingFunctionType: Bool {
        guard let arrow = typeName.range(of: "->") else {
            return false
        }
        return typeName[typeName.startIndex..<arrow.lowerBound]
            .split(whereSeparator: { !$0.isLetter })
            .contains("throws")
    }
}
