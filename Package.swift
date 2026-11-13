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
    name: "Canta",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Canta", targets: ["Canta"]),
        .library(name: "CantaAgentKit", targets: ["CantaAgentKit"])
    ],
    targets: [
        .target(
            name: "CantaAgentKit",
            path: "Sources/CantaAgentKit"
        ),
        .executableTarget(
            name: "Canta",
            dependencies: ["CantaAgentKit"],
            path: "Sources/Canta",
            resources: [
                .copy("Resources/Seed"),
                .copy("Resources/AppIcon")
            ]
        ),
        .testTarget(
            name: "CantaAgentKitTests",
            dependencies: ["CantaAgentKit"],
            path: "Tests/CantaAgentKitTests",
            swiftSettings: testSwiftSettings,
            linkerSettings: testLinkerSettings
        )
    ],
    swiftLanguageModes: [.v5]
)