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
    /// The appearance and theme chosen, read here so the first frame shows them.
    @State private var look: Look

    init() {
        #if DEBUG
        // A fresh start forgets the look chosen too, before it is read. A launch argument
        // (`-appearance light`, `-theme slate`) still answers, from its own domain.
        if LaunchOptions.resetsStore {
            UserDefaults.standard.removeObject(forKey: Look.appearanceKey)
            UserDefaults.standard.removeObject(forKey: Look.themeKey)
        }
        #endif
        _look = State(initialValue: Look())
        do {
            store = try Store.open(.local)
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
            WorkoutLauncher(store: store, namer: namer, resetsStore: resetsStore)
                // The window itself is held, so the bars, sheets, alerts, and keyboard follow;
                // nil on Auto lets it follow the phone.
                .preferredColorScheme(look.colorScheme)
                .environment(\.theme, look.theme)
                .environment(look)
        }
    }
}

extension Logger {
    static let app = Logger(subsystem: "com.plusplusinc.plusplus", category: "app")
}
