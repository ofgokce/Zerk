import Zerk
import CrossCore

enum Imports {
    /// Answered by CrossCore — the edge the merger has to find.
    @ImportedInjectable
    static func api() -> ApiServicing { Zerk<ApiServicing>.inject() }

    /// Answered by nothing in this package. CrossCore has the name but does not
    /// export it, so this stays unresolved rather than being matched.
    @ImportedInjectable
    static func internalOnly() -> InternalOnly { Zerk<InternalOnly>.inject() }
}

/// Depends on the imported key, written module-qualified — one key only because
/// the file's own `import` named the module.
@Injectable
struct FeedViewModel {
    @InjectableProviding
    init(api: CrossCore.ApiServicing) {}
}

protocol InternalOnly {}
