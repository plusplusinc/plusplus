import DesignSystem
import OSLog
import SwiftUI
import WorkoutStore

@main
struct PlusPlusApp: App {
    /// Nil when the store won't open: the app still works, and nothing saves. Better than a
    /// crash at every launch, or a store quietly opened somewhere else.
    private let store: Store?
    private let namer: WorkoutNamer
    /// Whether to start from an empty store, as the UI tests do.
    private let resetsStore: Bool
    /// The appearance chosen, read here so the first frame shows it.
    @State private var look: Look

    init() {
        do {
            store = try Store.open(.local)
        } catch {
            Logger.app.fault("The store didn't open, so nothing will save: \(error)")
            store = nil
        }
        #if DEBUG
        namer = LaunchOptions.usesFallbackNames ? .muscleGroupsOnly : .standard
        resetsStore = LaunchOptions.resetsStore
        // A fresh start forgets the appearance chosen too, before it is read. A launch argument
        // (`-appearance light`) still answers, from its own domain.
        if resetsStore {
            for key in Look.keys {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        if LaunchOptions.turnsOffUIKitAnimations {
            UIView.setAnimationsEnabled(false)
        }
        #else
        namer = .standard
        resetsStore = false
        #endif
        _look = State(initialValue: Look())
    }

    var body: some Scene {
        WindowGroup {
            WorkoutLauncher(store: store, namer: namer, resetsStore: resetsStore)
                // The window itself is held, so the bars, sheets, alerts, and keyboard follow;
                // nil with Automatic on lets it follow the phone. Black belt draws only where
                // the scheme is dark (`Color.pp`).
                .preferredColorScheme(look.colorScheme)
                .environment(\.isBlackBelt, look.isBlackBelt)
                .environment(look)
        }
    }
}

extension Logger {
    static let app = Logger(subsystem: "com.plusplusinc.plusplus", category: "app")
}
