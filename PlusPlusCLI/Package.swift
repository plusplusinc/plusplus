// swift-tools-version: 6.0
import PackageDescription

// The plusplus CLI (docs/PLATFORM.md, issue #24): UX over a git clone of a
// workout repo. No GitHub auth — git is the transport and the auth. Builds
// and tests on macOS and Linux; all format logic comes from PlusPlusKit.
let package = Package(
    name: "PlusPlusCLI",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../PlusPlusKit"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "plusplus",
            dependencies: [
                .product(name: "PlusPlusKit", package: "PlusPlusKit"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "PlusPlusCLITests", dependencies: ["plusplus"]),
    ]
)
