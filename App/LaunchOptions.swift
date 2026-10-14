#if DEBUG
    import Foundation

    /// Launch arguments the UI tests pass, as `-name YES`. Compiled out of release builds.
    enum LaunchOptions {
        /// Start from an empty store.
        static var resetsStore: Bool {
            UserDefaults.standard.bool(forKey: "resetStore")
        }
    }
#endif
