//
//  ZerkInterjectionView.swift
//  Zerk
//

#if canImport(SwiftUI)
import SwiftUI

public extension View {

    /// Registers interjections for a preview.
    ///
    /// ```swift
    /// #Preview {
    ///     ContentView().interjecting {
    ///         #Interject<ApiServicing>(with: MockApi())
    ///     }
    /// }
    /// ```
    ///
    /// The closure is a plain `() -> Void`, not a `@ViewBuilder`, which is the
    /// whole point of it: written straight into a `#Preview` body, `#Interject`
    /// is a `Void` expression and the builder rejects it —
    /// `type '()' cannot conform to 'View'`. Nothing in statement position
    /// escapes that, declaration macros included, since the builder claims the
    /// item before the macro's role is resolved. Here there is no builder, so it
    /// reads plainly.
    ///
    /// Registration happens where a preview needs it: on the process-wide set,
    /// which outlives the closure. A task-local scope could not serve, because
    /// SwiftUI builds child views and re-runs `body` long after `#Preview` has
    /// returned.
    ///
    /// Which means a preview's interjections **accumulate**: two previews in one
    /// file that both interject the same key leave whichever ran last in force.
    /// Register everything a preview needs rather than relying on a neighbour.
    ///
    /// Outside a preview this traps, exactly as an unscoped `#Interject` does —
    /// a test must take a scope instead.
    func interjecting(_ register: () -> Void) -> Self {
        register()
        return self
    }
}
#endif
