// swift-tools-version:5.9
// Temporary Package.swift for building Ice without full Xcode (SPM build only).
// The canonical build path remains Ice.xcodeproj with Xcode.

import PackageDescription

let package = Package(
    name: "Ice",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.5.2"),
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern", from: "1.0.0"),
        .package(url: "https://github.com/tmandry/AXSwift", from: "0.3.2"),
        .package(url: "https://github.com/buh/CompactSlider", exact: "1.1.5"),
        .package(url: "https://github.com/ukushu/Ifrit", from: "2.0.3"),
    ],
    targets: [
        .executableTarget(
            name: "Ice",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "LaunchAtLogin", package: "LaunchAtLogin-Modern"),
                .product(name: "AXSwift", package: "AXSwift"),
                .product(name: "CompactSlider", package: "CompactSlider"),
                .product(name: "IfritStatic", package: "Ifrit"),
            ],
            path: "Ice",
            exclude: [
                "Info.plist",
                "Ice.entitlements",
                "Resources",
            ],
            resources: [
                .process("Assets.xcassets"),
            ]
        ),
    ]
)
