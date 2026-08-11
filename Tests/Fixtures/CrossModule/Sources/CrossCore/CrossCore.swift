import Zerk

/// Exported, so another module can import the key.
public protocol ApiServicing: AnyObject {}

@Singleton
@Injectable<ApiServicing>(public: true)
public final class ApiService: ApiServicing {
    @InjectableProviding
    public init() {}
}

/// Deliberately *not* exported. A same-named import in another module must not
/// match this, because its generated members are internal — nothing outside
/// this module could reach them.
protocol InternalOnly {}

@Injectable<InternalOnly>
struct InternalService: InternalOnly {
    @InjectableProviding
    init() {}
}
