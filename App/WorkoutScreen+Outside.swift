import DesignSystem
import Session
import SwiftUI
import WorkoutStore

/// An action from the Watch, while the workout screen shows: stored as a tap's would be, and
/// shown at once. A set logged on the wrist lands without its motion, settled to what the store
/// holds; no motion is better than a wrong one. Finish and Discard end as their taps do.
extension WorkoutScreen {
    func perform(outside action: WorkoutAction, at date: Date) {
        switch action {
        case .finish:
            finish()
        case .discard:
            _ = end(session.discard)
        case .pause, .resume:
            withAnimation(liveKey.pauseMovesKey ? SetMotion.restSwap : nil) {
                session.apply(action, at: date)
            }
        default:
            session.apply(action, at: date)
            settleAtOnce()
        }
    }
}
