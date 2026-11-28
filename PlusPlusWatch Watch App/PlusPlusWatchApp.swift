#if canImport(Session)
import SwiftUI

/// The Watch app: one workout in progress, followed and logged from the wrist, with the phone.
/// It draws on the Watch's own black with PlusPlus's dark colors; the phone's look does not
/// reach it yet.
@main
struct PlusPlusWatchApp: App {
    var body: some Scene {
        WindowGroup {
            IdlePage()
                .preferredColorScheme(.dark)
        }
    }
}
#endif
