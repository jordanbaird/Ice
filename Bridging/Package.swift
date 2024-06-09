// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Bridging",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "Bridging",
            targets: ["Bridging"]
        ),
    ],
    targets: [
        .target(
            name: "Bridging",
            dependencies: ["CGSInternal"],
            swiftSettings: [
                .enableExperimentalFeature("AccessLevelOnImport"),
            ]
        ),
        .target(
            name: "CGSInternal",
            publicHeadersPath: "include"
        ),
    ]
)
