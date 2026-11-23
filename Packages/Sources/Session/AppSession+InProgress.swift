import Foundation
import WorkoutStore

/// The workout in progress: a pause, a set logged, and the rest after it, each through
/// `change(_:)`.
extension AppSession {
    /// Pauses the workout, or resumes it if paused.
    public func togglePause(at now: Date = .now) {
        guard let loggedWorkout else { return }
        change(.save(
            loggedWorkout.isPaused
                ? loggedWorkout.resuming(at: now)
                : loggedWorkout.pausing(at: now),
        ))
    }

    /// Logs `planned`, a set of `row`, at the numbers `row` plans now, or a timed set at the time
    /// its count has run (`LiveWorkout.logging`).
    public func log(_ planned: PlannedSet, of row: WorkoutExercise, at now: Date = .now) {
        guard let loggedWorkout else { return }
        let live = LiveWorkout(workout: current, loggedWorkout: loggedWorkout)
        change(.save(live.logging(planned, of: row, at: now)))
    }

    /// Extends the rest running after the last set by `seconds`, unless it is over. `override`,
    /// for the UI tests, is every rest's length (`LiveWorkout.rest(override:)`).
    public func extendRest(by seconds: Int, override: Int? = nil, at now: Date = .now) {
        changeLive { $0.extendingRest(by: seconds, override: override, at: now) }
    }

    /// Ends the rest running after the last set now, unless it is over
    /// (`LiveWorkout.skippingRest(override:at:)`).
    public func skipRest(override: Int? = nil, at now: Date = .now) {
        changeLive { $0.skippingRest(override: override, at: now) }
    }
}
