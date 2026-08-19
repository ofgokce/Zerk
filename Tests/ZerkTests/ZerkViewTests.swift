//
//  ZerkViewTests.swift
//  Zerk
//

#if canImport(SwiftUI)
import SwiftUI
import Testing
import ZerkTesting
@testable import Zerk

protocol PreviewServing {
    var tag: String { get }
}

@Injectable<PreviewServing>
struct LivePreviewService: PreviewServing {
    let tag = "live"

    @InjectableProviding
    init() {}
}

struct MockPreviewService: PreviewServing {
    let tag = "mock"
}

/// Injects its own dependency, which is the shape the ordering matters for: the
/// property resolves inside `init`, so anything registered afterwards is too
/// late for it.
struct InjectingPreviewView: View {
    @Injected var service: PreviewServing
    var body: some View { Text(service.tag) }
}

/// Two levels deep, and holding the child concretely so a test can reach it —
/// `body` is opaque. Both levels resolve during `init`, which is what makes this
/// the shape a modifier-based API gets wrong.
struct NestingPreviewView: View {
    @Injected var service: PreviewServing
    let child = InjectingPreviewView()
    var body: some View { child }
}

/// `Zerk.view(_:withInterjections:)` exists for one guarantee — the doubles are
/// registered *before* the content is built — and that guarantee is invisible
/// from its signature. These pin it.
///
/// Runs in parallel: every test opens its own interjection scope, which is
/// task-local, and nothing here touches shared mutable state.
@Suite("Zerk.view")
struct ZerkViewTests {

    @Test("interjections are in force while the content is built")
    @MainActor
    func registersBeforeBuildingContent() {
        Zerk.withInterjections {
            let view = Zerk.view {
                InjectingPreviewView()
            } withInterjections: {
                #Interject<PreviewServing>(with: MockPreviewService())
            }

            // The root view's *own* `@Injected` property. Resolved during
            // `InjectingPreviewView()`, which runs after the registration — so
            // it sees the double. Build the view first and this reads "live".
            #expect(view.service.tag == "mock")
        }
    }

    @Test("the ordering holds for nested views too")
    @MainActor
    func nestedViewsAlsoSeeTheDouble() {
        Zerk.withInterjections {
            let view = Zerk.view {
                NestingPreviewView()
            } withInterjections: {
                #Interject<PreviewServing>(with: MockPreviewService())
            }

            #expect(view.service.tag == "mock")
            #expect(view.child.service.tag == "mock")
        }
    }

    @Test("without interjections the real graph is used")
    @MainActor
    func withoutInterjectionsResolvesTheRealGraph() {
        Zerk.withInterjections {
            let view = Zerk.view {
                InjectingPreviewView()
            } withInterjections: {
                // Deliberately empty: the function must not alter resolution on
                // its own, only sequence what the closure registers.
            }

            #expect(view.service.tag == "live")
        }
    }

    @Test("the content closure takes a multi-statement builder body")
    @MainActor
    func contentIsAViewBuilder() {
        Zerk.withInterjections {
            let view = Zerk.view {
                Text("first")
                InjectingPreviewView()
            } withInterjections: {
                #Interject<PreviewServing>(with: MockPreviewService())
            }

            // Two statements, so `Content` solves as a tuple rather than one
            // view — which is what `@ViewBuilder` is on the parameter for.
            #expect(view.value.1.service.tag == "mock")
        }
    }

    @Test("the content closure runs exactly once")
    @MainActor
    func contentIsBuiltOnce() {
        nonisolated(unsafe) var builds = 0
        Zerk.withInterjections {
            _ = Zerk.view {
                let _ = { builds += 1 }()
                InjectingPreviewView()
            } withInterjections: {
                #Interject<PreviewServing>(with: MockPreviewService())
            }
        }
        #expect(builds == 1)
    }

    @Test("a member-specific interjection reaches the content too")
    @MainActor
    func memberInterjectionAlsoApplies() {
        Zerk.withInterjections {
            let view = Zerk.view {
                InjectingPreviewView()
            } withInterjections: {
                #Interject(\.livePreviewService, with: MockPreviewService())
            }

            #expect(view.service.tag == "mock")
        }
    }
}
#endif
