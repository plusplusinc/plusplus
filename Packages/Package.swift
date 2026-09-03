// swift-tools-version: 6.2
import PackageDescription

// One package; each target is a layer. A target cannot import anything it does not list, so
// the layering in CLAUDE.md is enforced by the compiler. Targets are added when they have code.

// Declared before `package`: a manifest is top-level script code, and a global read before its
// declaration is silently empty rather than an error.

/// Swift 6 language mode plus the same upcoming features the app enables in Base.xcconfig.
/// Nonisolated by default: storage code runs on whatever actor calls it.
let strict: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

/// UI targets: everything is main-actor isolated unless it says otherwise, matching the app.
let mainActorByDefault: [SwiftSetting] = strict + [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "PlusPlusKit",
    platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "WorkoutStore", targets: ["WorkoutStore"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.19.4"),
    ],
    targets: [
        .target(name: "WorkoutStore", swiftSettings: strict),
        .target(
            name: "DesignSystem",
            resources: [.process("Resources")],
            swiftSettings: mainActorByDefault,
        ),
        .testTarget(
            name: "WorkoutStoreTests",
            dependencies: ["WorkoutStore"],
            swiftSettings: strict,
        ),
        .testTarget(
            name: "DesignSystemTests",
            dependencies: [
                "DesignSystem",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            swiftSettings: mainActorByDefault,
        ),
    ],
)
