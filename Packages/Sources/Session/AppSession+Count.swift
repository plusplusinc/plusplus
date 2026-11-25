import Foundation
import WorkoutStore

/// A set's "Start in" and a timed set's count: each change through `LiveWorkout`'s rules and
/// `change(_:)`.
extension AppSession {
    /// Begins the current set's count, when it has none and one is due: as a rest before it
    /// ends, or as the screen lands on it. `override`, for the UI tests, is every rest's length.
    public func beginCount(override: Int? = nil, at now: Date = .now) {
        changeLive { $0.beginningCount(at: now, restOverride: override) }
    }

    /// Start has landed on the first set: its "Start in" begins now, and the workout's time
    /// starts as it ends (`LiveWorkout.landingStart(at:restOverride:)`). Nothing, for a workout
    /// started from the Workouts screen, whose "Start in" began at Start (`start(on:at:)`).
    public func landOnFirstSet(override: Int? = nil, at now: Date = .now) {
        changeLive { $0.landingStart(at: now, restOverride: override) }
    }

    /// Adds `seconds` to the timed set counting, unless it is over.
    public func extendCount(by seconds: Int, at now: Date = .now) {
        changeLive { $0.extendingCount(by: seconds, at: now) }
    }

    /// Logs a count that ran out while the app was away, then begins the next set's count.
    public func catchUp(override: Int? = nil, at now: Date = .now) {
        changeLive { $0.caughtUp(at: now, restOverride: override) }
    }

    /// Changes the workout through a rule on it, storing only a change.
    func changeLive(_ rule: (LiveWorkout) -> LoggedWorkout) {
        guard let loggedWorkout else { return }
        let changed = rule(LiveWorkout(workout: current, loggedWorkout: loggedWorkout))
        if changed != loggedWorkout {
            change(.save(changed))
        }
    }
}
