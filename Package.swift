// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "Zerk",
    platforms: [.iOS(.v9)],
    products: [
        .library(
            name: "Zerk",
            targets: ["Zerk"]),
    ],
    targets: [
        .target(
            name: "Zerk",
            dependencies: []),
        .testTarget(
            name: "ZerkTests",
            dependencies: ["Zerk"]),
    ]
)
