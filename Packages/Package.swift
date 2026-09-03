// swift-tools-version: 6.2
import PackageDescription

// One package, four targets. The dependency graph below is the architecture: a target cannot
// import anything it does not list, so the layering in CLAUDE.md is enforced by the compiler.
//
//   Features ──> DesignSystem
//        └─────> WorkoutStore ──> WorkoutCore

// Declared before `package`: a manifest is top-level script code, and a global read before its
// declaration is silently empty rather than an error.

/// Swift 6 language mode plus the same upcoming features the app enables in Base.xcconfig.
/// Nonisolated by default: these targets run on any actor, including the Watch's.
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
        .library(name: "WorkoutCore", targets: ["WorkoutCore"]),
        .library(name: "WorkoutStore", targets: ["WorkoutStore"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "Features", targets: ["Features"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.19.4"),
    ],
    targets: [
        .target(name: "WorkoutCore", swiftSettings: strict),
        .target(name: "WorkoutStore", dependencies: ["WorkoutCore"], swiftSettings: strict),
        .target(
            name: "DesignSystem",
            resources: [.process("Resources")],
            swiftSettings: mainActorByDefault,
        ),
        .target(
            name: "Features",
            dependencies: ["WorkoutCore", "WorkoutStore", "DesignSystem"],
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
