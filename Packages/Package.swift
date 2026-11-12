// swift-tools-version: 6.4
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
    platforms: [.iOS(.v27), .watchOS(.v27), .macOS(.v27)],
    products: [
        // `Session` rides in this product, so the app links it with no change to the project.
        .library(name: "WorkoutStore", targets: ["WorkoutStore", "Session"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.19.4"),
    ],
    targets: [
        .target(name: "WorkoutStore", swiftSettings: strict),
        // Observable state over the store, with no UI framework: the routine open and its
        // workout. Main-actor, as the screens that read it are.
        .target(name: "Session", dependencies: ["WorkoutStore"], swiftSettings: mainActorByDefault),
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
            name: "SessionTests",
            dependencies: ["Session", "WorkoutStore"],
            swiftSettings: mainActorByDefault,
        ),
        .testTarget(
            name: "DesignSystemTests",
            dependencies: [
                "DesignSystem",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            // Reference images ship inside the test bundle: Xcode Cloud runs tests on a machine
            // that has the built products but not the source checkout.
            resources: [.copy("__Snapshots__")],
            swiftSettings: mainActorByDefault,
        ),
    ],
)
