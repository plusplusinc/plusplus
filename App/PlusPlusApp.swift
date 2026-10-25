import DesignSystem
import OSLog
import SwiftUI
import WorkoutStore

@main
struct PlusPlusApp: App {
    /// Nil when the store won't open: the app still works, and nothing saves. Better than a
    /// crash at every launch, or a store quietly opened somewhere else.
    private let store: RoutineStore?
    private let namer: RoutineNamer
    /// Whether to start from an empty store, as the UI tests do.
    private let resetsStore: Bool

    init() {
        probe("launch args=\(ProcessInfo.processInfo.arguments.dropFirst().joined(separator: " "))")
        do {
            store = try RoutineStore.open(.local)
        } catch {
            Logger.app.fault("The store didn't open, so nothing will save: \(error)")
            store = nil
        }
        #if DEBUG
        namer = LaunchOptions.usesFallbackNames ? .muscleGroupsOnly : .standard
        resetsStore = LaunchOptions.resetsStore
        if LaunchOptions.turnsOffUIKitAnimations {
            UIView.setAnimationsEnabled(false)
        }
        #else
        namer = .standard
        resetsStore = false
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RoutineLauncher(store: store, namer: namer, resetsStore: resetsStore)
                .publishesHotReloads()
        }
    }
}

extension Logger {
    static let app = Logger(subsystem: "com.plusplusinc.plusplus", category: "app")
}
