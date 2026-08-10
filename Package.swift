// swift-tools-version:6.1

import PackageDescription
import CompilerPluginSupport

let package = Package(
    
    name: "Zerk",
    
    platforms: [
        .iOS(.v13),
        .macOS(.v14),
        .macCatalyst(.v13),
        .watchOS(.v6),
        .tvOS(.v13),
        .visionOS(.v1)
    ],
    
    products: [
        .library(
            name: "Zerk",
            targets: ["Zerk"]
        ),
        .plugin(
            name: "ZerkPlugin",
            targets: ["ZerkPlugin"]
        ),
        .library(
            name: "ZerkTesting",
            targets: ["ZerkTesting"]
        ),
    ],
    
    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-syntax.git",
            "602.0.0"..<"603.0.0"
        ),
    ],
    
    targets: [
        .target(
            name: "Zerk",
            dependencies: ["ZerkMacros"],
            // The only target whose code reaches a consumer's app binary, so it
            // is the only one that carries a privacy manifest. `.copy` rather
            // than `.process`: the manifest has to arrive as a readable plist
            // under its exact name for Xcode's privacy report to find it.
            resources: [
                .copy("PrivacyInfo.xcprivacy")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "ZerkTesting",
            dependencies: ["Zerk"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .macro(
            name: "ZerkMacros",
            dependencies: [
                "MacroToolkit",
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "CodegenToolkit",
            dependencies: [
                "SharedToolkit",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ],
            path: "Sources/Toolkits/Codegen",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .target(
            name: "SharedToolkit",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax")
            ],
            path: "Sources/Toolkits/Shared",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .target(
            name: "MacroToolkit",
            dependencies: [
                "SharedToolkit",
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax")
            ],
            path: "Sources/Toolkits/Macro",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "ZerkCodegen",
            dependencies: ["CodegenToolkit"],
            path: "Sources/ZerkCodegen",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .plugin(
            name: "ZerkPlugin",
            capability: .buildTool(),
            dependencies: ["ZerkCodegen"],
            path: "Sources/ZerkPlugin"
        ),
        .testTarget(
            name: "ZerkTests",
            dependencies: [
                "Zerk",
                "ZerkTesting",
                "MacroToolkit"
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ],
            plugins: ["ZerkPlugin"]
        ),
        .testTarget(
            name: "ZerkInjectionCodegenTests",
            dependencies: [
                "CodegenToolkit",
                .product(name: "SwiftParser", package: "swift-syntax")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
    ]
)
