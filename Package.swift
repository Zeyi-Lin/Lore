// swift-tools-version: 6.0
import Foundation
import PackageDescription

let cltFrameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
let cltInterop = "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
let hasCLTTesting = FileManager.default.fileExists(atPath: cltFrameworks + "/Testing.framework")
let testSwiftSettings: [SwiftSetting] = hasCLTTesting ? [.unsafeFlags(["-F", cltFrameworks])] : []
let testLinkerSettings: [LinkerSetting] = hasCLTTesting
    ? [.unsafeFlags([
        "-Xlinker", "-F", "-Xlinker", cltFrameworks,
        "-Xlinker", "-rpath", "-Xlinker", cltFrameworks,
        "-Xlinker", "-rpath", "-Xlinker", cltInterop
    ])]
    : []

let package = Package(
    name: "Lore",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Lore", targets: ["Lore"]),
        .library(name: "LoreAgentKit", targets: ["LoreAgentKit"])
    ],
    targets: [
        .target(
            name: "LoreAgentKit",
            path: "Sources/LoreAgentKit"
        ),
        .executableTarget(
            name: "Lore",
            dependencies: ["LoreAgentKit"],
            path: "Sources/Lore",
            resources: [
                .copy("Resources/Seed"),
                .copy("Resources/AppIcon")
            ]
        ),
        .testTarget(
            name: "LoreAgentKitTests",
            dependencies: ["LoreAgentKit"],
            path: "Tests/LoreAgentKitTests",
            swiftSettings: testSwiftSettings,
            linkerSettings: testLinkerSettings
        )
    ],
    swiftLanguageModes: [.v5]
)