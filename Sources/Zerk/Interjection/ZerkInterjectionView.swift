//
//  ZerkInterjectionView.swift
//  Zerk
//

#if canImport(SwiftUI)
import SwiftUI

public extension Zerk<Never> {

    /// Builds a preview's content with interjections already in force.
    ///
    /// ```swift
    /// #Preview {
    ///     Zerk.view {
    ///         ContentView()
    ///     } withInterjections: {
    ///         #Interject<ApiServicing>(with: MockApi())
    ///     }
    /// }
    /// ```
    ///
    /// ## The ordering is the whole point
    ///
    /// `content` is a *closure*, and it is called after `interjections()` — not
    /// evaluated at the call site. That one line of sequencing is what this
    /// function exists for.
    ///
    /// `@Injected` resolves when its enclosing value is **initialized**, so a
    /// view that injects its own dependency has already resolved it by the time
    /// anything can be registered against it:
    ///
    /// ```swift
    /// struct ContentView: View {
    ///     @Injected var api: ApiServicing   // resolved by `ContentView()`
    /// }
    /// ```
    ///
    /// Registering doubles *after* constructing that view — which is what a
    /// `ContentView().someModifier { … }` shape necessarily does, since the
    /// receiver is built before the modifier runs — leaves the root view holding
    /// the real graph while its children get the doubles. Half-mocked, and
    /// silently so. Taking the content as a closure is the only way to put
    /// registration first.
    ///
    /// So the two closures run in the opposite order to the one they are written
    /// in: `withInterjections` appears second and runs first. That is deliberate.
    /// The call site reads as "this view, with these doubles", and the sequencing
    /// needed to make that true lives here rather than at every use.
    ///
    /// ## Where the registration goes
    ///
    /// Onto the process-wide set, which outlives the closure. A task-local scope
    /// could not serve: SwiftUI builds child views and re-runs `body` long after
    /// `#Preview` has returned, by which point any binding would have unwound.
    ///
    /// Which means a preview's interjections **accumulate**. Two previews in one
    /// file that interject the same key leave whichever ran last in force, so
    /// register everything a preview needs rather than relying on a neighbour's.
    ///
    /// Outside a preview this traps, exactly as an unscoped `#Interject` does — a
    /// test must take a scope of its own with ``Zerk/withInterjections(_:)``.
    ///
    /// - Parameters:
    ///   - content: The view to build. `@ViewBuilder`, so it takes the same
    ///     multi-statement bodies any other SwiftUI closure does.
    ///   - interjections: The doubles to register. A plain `() -> Void` rather
    ///     than a `@ViewBuilder`, which is what lets `#Interject` be written
    ///     inside it at all: it is a `Void` expression, and a builder rejects one
    ///     with `type '()' cannot conform to 'View'`.
    /// - Returns: The content, built with the interjections in force. The
    ///   concrete `Content` rather than `some View`, so nothing is erased.
    static func view<Content: View>(@ViewBuilder _ content: () -> Content,
                                    withInterjections interjections: () -> Void) -> Content {
        interjections()
        return content()
    }
}
#endif
