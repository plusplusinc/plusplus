import OSLog
import SwiftUI

extension View {
    /// Keeps the screen from dimming and locking while `isOn` and the app is in front, as
    /// while a workout runs, paused or not, so it can be read mid-set without a touch.
    func keepsScreenOn(_ isOn: Bool) -> some View {
        modifier(KeepsScreenOn(isOn: isOn))
    }
}

private struct KeepsScreenOn: ViewModifier {
    let isOn: Bool
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.onChange(of: isOn && scenePhase == .active, initial: true) { _, keepsOn in
            guard UIApplication.shared.isIdleTimerDisabled != keepsOn else { return }
            UIApplication.shared.isIdleTimerDisabled = keepsOn
            // XCTest can't read the idle timer; the log shows each change.
            Logger.app.notice("Screen stays on: \(keepsOn, privacy: .public)")
        }
    }
}
