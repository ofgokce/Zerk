//
//  SingletonStorageTests.swift
//  Zerk
//

import Testing
@testable import CodegenToolkit

/// Whether a `@Singleton`'s storage slot carries `nonisolated(unsafe)`, over
/// every shape the stored type can take.
///
/// The annotation exists because `@Singleton`'s contract is that one instance is
/// shared across isolation domains, which Swift 6 otherwise requires the stored
/// type to be `Sendable` for. It was emitted unconditionally — and for a type
/// that *says* it is Sendable the compiler answers
/// "'nonisolated(unsafe)' is unnecessary for a constant with 'Sendable' type",
/// which is a build failure under `-warnings-as-errors`, inside a file the
/// developer cannot edit. It is also the shape Zerk's own conformance check
/// pushes them towards.
///
/// The other two storage forms had already learned this — an async box and a
/// `ZerkScopedBox` are both Sendable, and both branches say so in a comment —
/// so this is the third of three, written as a table because the question is one
/// question asked of several declarations.
@Suite("Singleton storage")
struct SingletonStorageTests {

    /// A stored type, and whether the slot needs the escape hatch.
    struct Storage {
        let name: String
        let declaration: String
        /// Whether `nonisolated(unsafe)` must appear.
        let needsEscapeHatch: Bool
        /// Whether the generated file is free of warnings. `false` only for the
        /// shape Zerk cannot see, which is a stated limit rather than a defect —
        /// asserted so the limit is pinned rather than merely written down.
        var isWarningFree: Bool = true

        static let all: [Storage] = [
            Storage(name: "no conformance",
                    declaration: "final class Cache {}",
                    needsEscapeHatch: true),
            Storage(name: "@unchecked Sendable",
                    declaration: "final class Cache: @unchecked Sendable {}",
                    needsEscapeHatch: false),
            Storage(name: "Sendable",
                    declaration: "final class Cache: Sendable {}",
                    needsEscapeHatch: false),
            Storage(name: "a protocol, then Sendable",
                    declaration: """
                    protocol Caching {}
                    final class Cache: Caching, @unchecked Sendable {}
                    """,
                    needsEscapeHatch: false),
            // Only the declaration's own clause is read. A conformance added in
            // an extension is invisible to syntax, so the hatch stays and the
            // warning with it — stated in Limitations.md rather than guessed at.
            Storage(name: "Sendable in an extension",
                    declaration: """
                    final class Cache {}
                    extension Cache: @unchecked Sendable {}
                    """,
                    needsEscapeHatch: true,
                    isWarningFree: false),
        ]
    }

    @Test("the escape hatch is emitted only where the compiler needs it",
          arguments: Storage.all)
    func escapeHatchTracksTheDeclaredConformance(storage: Storage) throws {
        let source = """
        \(storage.declaration.replacingOccurrences(
            of: "final class Cache",
            with: "@Singleton\n@Injectable\nfinal class Cache"))
        """

        let generated = CompileFixture.generate(source: source)

        #expect(generated.contains("static let cache: Cache = Cache()"),
                "\(storage.name):\n\(generated)")
        #expect(generated.contains("nonisolated(unsafe) static let cache") == storage.needsEscapeHatch,
                "\(storage.name):\n\(generated)")
    }

    /// And the generated file compiles **with warnings treated as errors**,
    /// which is the property this was actually about: a warning in a file the
    /// developer cannot edit is a build failure they cannot fix.
    ///
    /// One row is expected *not* to — the conformance written in an extension,
    /// which syntax cannot see. Asserted rather than skipped, so the limit is
    /// pinned: if Zerk ever learns to read it, this row fails and says so.
    @Test("the generated file has no warnings to be turned into errors",
          arguments: Storage.all)
    func generatedStorageIsWarningFree(storage: Storage) throws {
        var options = CompileFixture.Options.swift6
        options.extraFlags = ["-warnings-as-errors"]

        let compiled = try CompileFixture.run(
            source: """
            \(storage.declaration.replacingOccurrences(
                of: "final class Cache",
                with: "@Singleton\n@Injectable\nfinal class Cache"))
            """,
            options: options)

        try #require(!compiled.skipped)
        #expect(compiled.didCompile == storage.isWarningFree,
                Comment(rawValue: "\(storage.name)\n\(compiled.compilerOutput)\n\(compiled.generated)"))
    }
}

extension SingletonStorageTests.Storage: CustomTestStringConvertible {
    var testDescription: String { name }
}
