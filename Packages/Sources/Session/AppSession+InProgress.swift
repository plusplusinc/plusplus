import Foundation
import OSLog
import WorkoutStore

/// The workout in progress: a pause, a set logged, the rest after it, and its end, each through
/// `change(_:)`.
extension AppSession {
    /// Finishes the logged workout, keeping it with the name the workout shows now, and a timed
    /// set counting logged at the time done (`LiveWorkout.finishing(at:)`), and names it as the
    /// one Log has yet to bring into History (`justFinished`). With Apple Health on, saves it
    /// there too once its write has landed (`saveToHealth(_:pausedSince:)`).
    public func finish(at now: Date = .now) {
        guard let loggedWorkout else { return }
        var finished = LiveWorkout(workout: current, loggedWorkout: loggedWorkout)
            .finishing(at: now)
        finished.workoutName = shownName
        change(.save(finished))
        justFinished = finished.id
        deleteIfCleared()
        saveToHealth(finished, pausedSince: loggedWorkout.pausedAt)
    }

    /// Saves a workout just finished to Apple Health, if the system lets the app, after its
    /// write has landed. Not one paused and resumed before: when its pauses happened isn't kept
    /// (`HealthWorkout.init(finished:pausedSince:)`).
    private func saveToHealth(_ finished: LoggedWorkout, pausedSince: Date?) {
        health.refresh()
        guard health.access == .on else { return }
        guard let workout = HealthWorkout(finished: finished, pausedSince: pausedSince) else {
            Logger.session.notice("Not saved to Apple Health: its pauses' times aren't kept")
            return
        }
        Task {
            await loggedWorkoutWritesLanded()
            await health.save(workout)
        }
    }

    /// Whether the open workout has anything to delete: one with nothing saved has none, and
    /// one in progress is not deleted.
    public var canDeleteOpen: Bool {
        !current.isEmpty && loggedWorkout == nil
    }

    /// Ends the workout keeping nothing of it, as if Start never ran: Log has nothing to bring in.
    public func discard() {
        guard let loggedWorkout else { return }
        change(.discard(loggedWorkout.id))
        deleteIfCleared()
    }

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
