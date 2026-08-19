//
//  ProviderMemberName.swift
//  Zerk
//

/// What the member generated for a provider is called.
///
/// Two states rather than a `String?`, because `nil` is already taken further
/// down: `ProviderChoice.memberNameHint` uses it for "let the emitter decide",
/// and an imported record uses it for "there is no member at all". Naming both
/// here keeps a field that could mean three things from having to.
///
/// A required field with no default, for a reason the test fixtures found: a
/// defaulted one is a field a construction site can forget while still
/// compiling, and forgetting *this* one silently renames every member the
/// provider builds.
enum ProviderMemberName: Equatable {
    /// The provider states no name of its own — an initializer. Its member is
    /// named after the type it builds, which the emitter works out.
    case typeName
    /// Whatever the collector resolved: a factory's own name, an `@Injectable`
    /// declaration's, what `name:` says, or the produced type under
    /// `typeNamed:`.
    case stated(String)

    /// The name, or `nil` to leave it to the emitter.
    var text: String? {
        switch self {
        case .typeName:
            return nil
        case .stated(let name):
            return name
        }
    }
}
