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

    /// Start has landed on the first set: the workout's clock starts from now, and the set's
    /// count with it (`LiveWorkout.landingStart(at:restOverride:)`).
    public func startClockAtLanding(override: Int? = nil, at now: Date = .now) {
        changeLive { $0.landingStart(at: now, restOverride: override) }
    }

    /// Cuts "Start in" short: the set counts from now.
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
        guard let loggedWorkout else { return }
        let changed = rule(LiveWorkout(workout: current, loggedWorkout: loggedWorkout))
        if changed != loggedWorkout {
            change(.save(changed))
        }
    }
}
