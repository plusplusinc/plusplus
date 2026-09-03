// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WorkoutStore",
    platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "WorkoutStore", targets: ["WorkoutStore"]),
    ],
    dependencies: [
        .package(path: "../WorkoutCore"),
    ],
    targets: [
        .target(
            name: "WorkoutStore",
            dependencies: ["WorkoutCore"],
            swiftSettings: .shared,
        ),
        .testTarget(
            name: "WorkoutStoreTests",
            dependencies: ["WorkoutStore"],
            swiftSettings: .shared,
        ),
    ],
)

extension [SwiftSetting] {
    /// Applied to every target so a package can never silently drift from the app's strictness.
    /// Non-UI package: nonisolated by default so it runs on any actor, including the Watch's.
    static var shared: [SwiftSetting] {
        [
            .swiftLanguageMode(.v6),
            .enableUpcomingFeature("ExistentialAny"),
            // Approachable concurrency, as SWIFT_APPROACHABLE_CONCURRENCY does for the app.
            .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            .enableUpcomingFeature("InferIsolatedConformances"),
        ]
    }
}
