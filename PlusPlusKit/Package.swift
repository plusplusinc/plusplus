// swift-tools-version: 6.0
import PackageDescription

// The platform-pure core of PlusPlus: enums, metric/rep-target logic, and the
// interchange format (DTOs + deterministic codec + validation). No SwiftUI,
// no SwiftData — this package must build and test on Linux (see the kit-test
// CI job), because the CLI and MCP server depend on it running anywhere.
let package = Package(
    name: "PlusPlusKit",
    // Floors for Apple builds (the app targets iOS 26 anyway); no effect on
    // Linux. Needed because the codec uses .withoutEscapingSlashes (iOS 13+).
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "PlusPlusKit", targets: ["PlusPlusKit"])
    ],
    targets: [
        .target(name: "PlusPlusKit"),
        .testTarget(name: "PlusPlusKitTests", dependencies: ["PlusPlusKit"]),
    ]
)
