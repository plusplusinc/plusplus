import Foundation
import WorkoutStore

/// The Watch's actions on the phone: each reaches the store through `change(_:)`, as a tap's
/// does, by the same rule the Watch ran (`LiveWorkout.applying`).
extension AppSession {
    /// Applies `action` at `date`, the wrist's own time: Finish still names the workout and asks
    /// for Apple Health's catch-up, and Discard still deletes a workout cleared to nothing.
    public func apply(_ action: WorkoutAction, at date: Date) {
        switch action {
        case .finish: finish(at: date)
        case .discard: discard()
        case .pause: setPaused(true, at: date)
        case .resume: setPaused(false, at: date)
        default: changeLive { $0.applying(action, at: date) ?? $0.workoutSession }
        }
    }

    /// Pauses or resumes the workout; unchanged if it already is.
    public func setPaused(_ paused: Bool, at date: Date = .now) {
        guard let workoutSession, workoutSession.isPaused != paused else { return }
        change(.save(paused ? workoutSession.pausing(at: date) : workoutSession.resuming(at: date)))
    }

    /// An action from the Watch: handed to the workout screen when one shows, so it plays as a
    /// tap would, else applied here.
    public func receive(_ action: WorkoutAction, at date: Date) {
        if let outsidePlayer {
            outsidePlayer(action, date)
        } else {
            apply(action, at: date)
        }
    }
}
