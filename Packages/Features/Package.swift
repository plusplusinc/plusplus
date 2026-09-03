// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Features",
    platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "Features", targets: ["Features"]),
    ],
    dependencies: [
        .package(path: "../WorkoutCore"),
        .package(path: "../WorkoutStore"),
        .package(path: "../DesignSystem"),
    ],
    targets: [
        .target(
            name: "Features",
            dependencies: ["WorkoutCore", "WorkoutStore", "DesignSystem"],
            swiftSettings: .shared,
        ),
    ],
)

extension [SwiftSetting] {
    /// Applied to every target so a package can never silently drift from the app's strictness.
    /// UI package: everything is main-actor isolated unless it says otherwise, matching the app.
    static var shared: [SwiftSetting] {
        [
            .swiftLanguageMode(.v6),
            .enableUpcomingFeature("ExistentialAny"),
            // Approachable concurrency, as SWIFT_APPROACHABLE_CONCURRENCY does for the app.
            .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            .enableUpcomingFeature("InferIsolatedConformances"),
            .defaultIsolation(MainActor.self),
        ]
    }
}
