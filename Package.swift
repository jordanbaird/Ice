// swift-tools-version:6.0
import PackageDescription

// Test-only package. It compiles Ice's pure macOS 27 logic so that logic can be
// unit tested with `swift test`. The same files are compiled into the Ice app
// through the synchronized `Ice` folder group.
let package = Package(
    name: "IceMacOS27Core",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "IceMacOS27Core",
            path: "Ice/MenuBar/MacOS27/Core",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "IceMacOS27CoreTests",
            dependencies: ["IceMacOS27Core"],
            path: "Tests/IceMacOS27CoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
