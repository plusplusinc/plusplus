// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WorkoutStore",
    platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "WorkoutStore", targets: ["WorkoutStore"])
    ],
    dependencies: [
        .package(path: "../WorkoutCore")
    ],
    targets: [
        .target(
            name: "WorkoutStore",
            dependencies: ["WorkoutCore"],
            swiftSettings: .shared
        ),
        .testTarget(
            name: "WorkoutStoreTests",
            dependencies: ["WorkoutStore"],
            swiftSettings: .shared
        ),
    ]
)

extension [SwiftSetting] {
    static var shared: [SwiftSetting] {
        [
            .swiftLanguageMode(.v6),
            .enableUpcomingFeature("ExistentialAny"),
        ]
    }
}
