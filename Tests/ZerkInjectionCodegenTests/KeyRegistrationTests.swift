//
//  KeyRegistrationTests.swift
//  Zerk
//

import Testing
import SwiftParser
@testable import CodegenToolkit

/// `public: true` over every way of registering a key, against every shape a key
/// can take.
///
/// Four collectors establish keys, and the export check reads what they record:
/// whether *every* nominal type the key mentions is public. Three of them
/// recorded those names and one recorded only the key's spelling, which passed
/// the check vacuously — the fallback is the key's own text, and that matches a
/// declared name for `Hidden` while matching nothing for `Cache<Hidden>`. So the
/// same value asked for the same export was refused when swept and silently
/// granted when annotated, and the generated file did not compile.
///
/// A cross product rather than a case per collector: what differed was the
/// *pair*, and the shape that gave it away — a generic application — is one that
/// no single-declaration test happened to use.
@Suite("Key registration and export")
struct KeyRegistrationTests {

    /// A key shape, and the internal type it hides.
    struct Shape {
        let name: String
        /// Declarations the fixture needs, with `Hidden` left internal.
        let declarations: String
        /// The key as written on the declaration.
        let key: String
        /// An expression producing one, for a value's body.
        let value: String

        static let all: [Shape] = [
            Shape(name: "bare",
                  declarations: "struct Hidden { init() {} }",
                  key: "Hidden", value: "Hidden()"),
            Shape(name: "nested",
                  declarations: "public enum Outer { struct Hidden { public init() {} } }",
                  key: "Outer.Hidden", value: "Outer.Hidden()"),
            Shape(name: "specialization",
                  declarations: """
                  struct Hidden {}
                  public struct Cache<E> { public init() {} }
                  """,
                  key: "Cache<Hidden>", value: "Cache<Hidden>()"),
            Shape(name: "composition",
                  declarations: """
                  public protocol Alpha {}
                  protocol Hidden {}
                  public struct Impl: Alpha, Hidden { public init() {} }
                  """,
                  key: "any Alpha & Hidden", value: "Impl()"),
            Shape(name: "optional",
                  declarations: "struct Hidden { init() {} }",
                  key: "Hidden?", value: "Hidden()"),
            Shape(name: "array",
                  declarations: "struct Hidden { init() {} }",
                  key: "[Hidden]", value: "[]"),
        ]
    }

    /// A way of registering a key while asking for a public member.
    struct Registration {
        let name: String
        let declaration: (Shape) -> String

        static let all: [Registration] = [
            Registration(name: "@Injectable type") { shape in
                """
                @Injectable<\(shape.key)>(public: true)
                public struct Impl2: Hidden {}
                """
            },
            Registration(name: "@Injectable declaration") { shape in
                """
                @Injectable<\(shape.key)>(public: true)
                public func make() -> \(shape.key) { \(shape.value) }
                """
            },
            Registration(name: "@InjectableValue") { shape in
                """
                @InjectableValue(public: true)
                public var thing: \(shape.key) { \(shape.value) }
                """
            },
            Registration(name: "@InjectableValues sweep") { shape in
                """
                @InjectableValues(public: true)
                public enum Config {
                    public static var thing: \(shape.key) { \(shape.value) }
                }
                """
            },
        ]
    }

    @Test("public: true is refused whenever any part of the key is internal",
          arguments: Registration.all, Shape.all)
    func exportIsRefusedForInternalComponents(registration: Registration, shape: Shape) {
        // The `@Injectable` type row needs something to conform to, and only the
        // composition shape provides a protocol — the others register the type
        // by a written key instead.
        guard registration.name != "@Injectable type" || shape.name == "composition" else {
            return
        }

        let result = CompileFixture.generateWithResolution(source: """
        \(shape.declarations)

        \(registration.declaration(shape))
        """)

        #expect(result.diagnostics.contains {
            $0.severity == .warning && $0.message.contains("has no effect")
        }, "\(registration.name)/\(shape.name): \(result.diagnostics.map(\.message))")
        #expect(!result.output.output.contains("public static"),
                "\(registration.name)/\(shape.name) emitted public members")
    }

    @Test("public: true is honoured when every part is public",
          arguments: Registration.all)
    func exportIsAllowedWhenEverythingIsPublic(registration: Registration) {
        let shown = Shape(name: "public specialization",
                          declarations: """
                          public struct Shown {}
                          public struct Cache<E> { public init() {} }
                          public protocol Hidden {}
                          """,
                          key: "Cache<Shown>", value: "Cache<Shown>()")

        guard registration.name != "@Injectable type" else { return }

        let result = CompileFixture.generateWithResolution(source: """
        \(shown.declarations)

        \(registration.declaration(shown))
        """)

        #expect(result.diagnostics.isEmpty,
                "\(registration.name): \(result.diagnostics.map(\.message))")
        #expect(result.output.output.contains("public static"),
                "\(registration.name) emitted no public members")
    }

    /// The invariant behind all of the above: a key's spelling and the types it
    /// mentions are recorded together, so no registration can leave the export
    /// check with nothing to judge.
    ///
    /// `isPublishable` falls back to the key's own text for a record built by
    /// hand in a test. This is what keeps that fallback describing only tests —
    /// it was the collector too, and nothing said so.
    @Test("every key the collector registers carries its nominal names")
    func everyRegisteredKeyCarriesItsNames() {
        let collector = SourceCollector(settings: .default)
        collector.walk(Parser.parse(source: """
        public protocol Alpha {}
        struct Hidden {}
        public struct Cache<E> { public init() {} }
        public struct Box<E> { public init() {} }
        public struct Bag<E> { public init() {} }

        @Injectable<any Alpha>(public: true)
        public struct Impl: Alpha { public init() {} }

        // A distinct key per registration, so no collector can be carried by
        // another one that happened to name the same key.
        @Injectable<Cache<Hidden>>
        public func make() -> Cache<Hidden> { Cache<Hidden>() }

        @InjectableValue
        public var thing: Box<Hidden> { Box<Hidden>() }

        @InjectableValues
        public enum Config {
            public static var swept: Bag<Hidden> { Bag<Hidden>() }
        }
        """))

        for key in collector.keyDisplayNames.keys {
            #expect(collector.keyNominalNames[key]?.isEmpty == false,
                    "'\(key)' was registered with no nominal names")
        }
        #expect(!collector.keyDisplayNames.isEmpty)
    }
}

extension KeyRegistrationTests.Registration: CustomTestStringConvertible {
    var testDescription: String { name }
}

extension KeyRegistrationTests.Shape: CustomTestStringConvertible {
    var testDescription: String { name }
}
