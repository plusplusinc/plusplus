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

    /// Run UIKit's animations, such as the keyboard rising and a sheet sliding up, without
    /// motion. XCTest waits after every action until it has seen each UIKit animation it saw
    /// start also stop. On a keyboard rise or a sheet, UIKit sometimes reports one animation's
    /// start twice and its stop once, and every later wait in that launch then runs out its 60 s.
    /// With no UIKit animations there is nothing to miscount. SwiftUI's own animations still run.
    static var turnsOffUIKitAnimations: Bool {
        UserDefaults.standard.bool(forKey: "noUIKitAnimations")
    }
}
#endif
