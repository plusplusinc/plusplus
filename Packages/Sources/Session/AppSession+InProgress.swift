import Foundation
import WorkoutStore

/// The workout in progress: a pause, a set logged, the rest after it, and its end, each through
/// `change(_:)`.
extension AppSession {
    /// Finishes the logged workout, keeping it with the name the workout shows now, and a timed
    /// set counting logged at the time done (`LiveWorkout.finishing(at:)`), and names it as the
    /// one Log has yet to bring into History (`justFinished`), with its Apple Health type as
    /// what it logged makes it now. With Apple Health on, the catch-up after its write has
    /// landed saves it there from what the store keeps (`catchUpHealth()`); whether the system
    /// lets the app is read then, not in the Finish tap's turn.
    public func finish(at now: Date = .now) {
        guard let loggedWorkout else { return }
        var finished = LiveWorkout(workout: current, loggedWorkout: loggedWorkout)
            .finishing(at: now)
        finished.workoutName = shownName
        finished.healthActivity = HealthActivity(logged: finished.sets, in: exercises)
        change(.save(finished))
        // In the log from the finish, not from the read after its write lands, so Log's first
        // frame after it already holds it, and the Health card is there with it
        // (`healthPrompt`); History leaves it out until it comes in (`justFinished`).
        log = log.map { WorkoutLog(loggedWorkouts: $0.loggedWorkouts + [finished]) }
        justFinished = finished.id
        deleteIfCleared()
        health.offerAtFinish()
        catchUpHealth()
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

    /// Extends the rest running after the last set by `seconds`, unless it is over.
    public func extendRest(by seconds: Int, at now: Date = .now) {
        changeLive { $0.extendingRest(by: seconds, at: now) }
    }

    /// Ends the rest running after the last set now, unless it is over
    /// (`LiveWorkout.skippingRest(at:)`).
    public func skipRest(at now: Date = .now) {
        changeLive { $0.skippingRest(at: now) }
    }
}
