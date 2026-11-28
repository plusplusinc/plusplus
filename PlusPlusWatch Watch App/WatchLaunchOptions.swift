#if canImport(Session)
import Foundation
import WorkoutStore

/// Debug launch arguments, read once at launch, so a screenshot shows one fixed state of the
/// boards: `-watchState <WatchFixture>` (or `demo`), `-watchPage time|set|list`,
/// `-watchFreeze YES` to hold the clock at the fixture's moment, and `-watchDim YES` for wrist
/// down. Release builds read none of them.
struct WatchLaunchOptions {
    var state: String?
    var page: String?
    var freeze = false
    var dim = false

    static let current: Self = {
        #if DEBUG
        let defaults = UserDefaults.standard
        return Self(
            state: defaults.string(forKey: "watchState"),
            page: defaults.string(forKey: "watchPage"),
            freeze: defaults.bool(forKey: "watchFreeze"),
            dim: defaults.bool(forKey: "watchDim"),
        )
        #else
        return Self()
        #endif
    }()

    #if DEBUG
    /// The fixture named by `-watchState`, if it names one.
    var fixture: WatchFixture? {
        state.flatMap(WatchFixture.init(rawValue:))
    }
    #endif
}
#endif
