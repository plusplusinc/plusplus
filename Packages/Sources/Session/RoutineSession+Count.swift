import Foundation
import WorkoutStore

/// A timed set's count: each change through `LiveWorkout`'s rules and `change(_:)`.
extension RoutineSession {
    /// Begins the current set's count, when it is timed and has none: as a rest before it ends.
    /// `override`, for the UI tests, is every rest's length.
    public func beginCount(override: Int? = nil, at now: Date = .now) {
        changeLive { $0.beginningCount(at: now, restOverride: override) }
    }

    /// Cuts "Starts in" short: the set counts from now.
    public func startCountNow(at now: Date = .now) {
        changeLive { $0.startingCountNow(at: now) }
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
        guard let workout else { return }
        let changed = rule(LiveWorkout(routine: current, workout: workout))
        if changed != workout {
            change(.save(changed))
        }
    }
}
