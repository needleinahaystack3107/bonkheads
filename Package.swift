// swift-tools-version:5.10
import PackageDescription

// Native arm64 macOS build: `swift build -c release`, then run .build/release/Bonkheads.
// Only Apple frameworks (AppKit + SpriteKit) are used, so nothing needs installing.
let package = Package(
    name: "Bonkheads",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Bonkheads",
            path: "src",
            swiftSettings: [.unsafeFlags(["-Osize"], .when(configuration: .release))]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
