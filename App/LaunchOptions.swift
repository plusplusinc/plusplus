#if DEBUG
import Foundation

/// Launch arguments the UI tests pass, as `-name YES`. Compiled out of release builds.
enum LaunchOptions {
    /// Start from an empty store.
    static var resetsStore: Bool {
        UserDefaults.standard.bool(forKey: "resetStore")
    }

    /// Name routines from their muscle groups, never the model, so a test sees the same name
    /// on any simulator.
    static var usesFallbackNames: Bool {
        UserDefaults.standard.bool(forKey: "fallbackNames")
    }
}
#endif
