// swift-tools-version:6.2

import PackageDescription

/// A two-module package whose only job is to be resolved by Zerk.
///
/// `CrossModuleGraphTests` reads these sources directly, so the cross-module
/// stitching is covered on every `swift test` without a nested build. The same
/// package is what `ZERK_E2E=1` drives `swift package zerk graph` against.
/// One fixture for both, so the fast test cannot drift from what the CLI sees.
let package = Package(
    name: "CrossModule",
    platforms: [.macOS(.v14)],
    dependencies: [
        // The Zerk package this fixture lives inside.
        .package(path: "../../..")
    ],
    targets: [
        .target(
            name: "CrossCore",
            dependencies: [.product(name: "Zerk", package: "Zerk")],
            plugins: [.plugin(name: "ZerkPlugin", package: "Zerk")]
        ),
        .target(
            name: "CrossFeature",
            dependencies: ["CrossCore", .product(name: "Zerk", package: "Zerk")],
            plugins: [.plugin(name: "ZerkPlugin", package: "Zerk")]
        )
    ]
)
