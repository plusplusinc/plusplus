#if DEBUG
import Foundation

/// Launch arguments the UI tests pass, as `-name YES`. Compiled out of release builds.
enum LaunchOptions {
    /// Start from an empty store.
    static var resetsStore: Bool {
        UserDefaults.standard.bool(forKey: "resetStore")
    }

    /// Name routines from their muscle groups alone. A routine's style follows its id, so a test
    /// can't predict the standard name of a routine it just made; the muscle-group names are the
    /// same for every routine.
    static var usesFallbackNames: Bool {
        UserDefaults.standard.bool(forKey: "fallbackNames")
    }
}
#endif
