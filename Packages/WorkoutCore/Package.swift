// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WorkoutCore",
    platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "WorkoutCore", targets: ["WorkoutCore"]),
    ],
    targets: [
        .target(name: "WorkoutCore", swiftSettings: .shared),
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
