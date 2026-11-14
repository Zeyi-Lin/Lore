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
    name: "Lora",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Lora", targets: ["Lora"]),
        .library(name: "LoraAgentKit", targets: ["LoraAgentKit"])
    ],
    targets: [
        .target(
            name: "LoraAgentKit",
            path: "Sources/LoraAgentKit"
        ),
        .executableTarget(
            name: "Lora",
            dependencies: ["LoraAgentKit"],
            path: "Sources/Lora",
            resources: [
                .copy("Resources/Seed"),
                .copy("Resources/AppIcon")
            ]
        ),
        .testTarget(
            name: "LoraAgentKitTests",
            dependencies: ["LoraAgentKit"],
            path: "Tests/LoraAgentKitTests",
            swiftSettings: testSwiftSettings,
            linkerSettings: testLinkerSettings
        )
    ],
    swiftLanguageModes: [.v5]
)