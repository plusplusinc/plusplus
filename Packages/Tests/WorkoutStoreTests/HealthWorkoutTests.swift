import Foundation
import Testing
@testable import WorkoutStore

/// What a finished workout gives Apple Health: its start and end, and only pauses whose times
/// are known.
@Suite("Health workout")
struct HealthWorkoutTests {
    private static func at(_ seconds: Double) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    private static func started() -> LoggedWorkout {
        LoggedWorkout(workoutID: UUID(), workoutName: "Upper", startedAt: at(100))
    }

    @Test("A workout never paused goes with its start and end, and no pauses")
    func neverPaused() throws {
        let finished = Self.started().finishing(at: Self.at(400))
        let workout = try #require(HealthWorkout(finished: finished, pausedSince: nil))
        #expect(workout.id == finished.id)
        #expect(workout.start == Self.at(100))
        #expect(workout.end == Self.at(400))
        #expect(workout.pauses.isEmpty)
    }

    @Test("A workout finished while paused goes with that pause, its length leaving it out")
    func finishedWhilePaused() throws {
        let paused = Self.started().pausing(at: Self.at(300))
        let finished = paused.finishing(at: Self.at(400))
        let workout = try #require(HealthWorkout(finished: finished, pausedSince: paused.pausedAt))
        #expect(workout.pauses == [DateInterval(start: Self.at(300), end: Self.at(400))])
        let active = workout.end.timeIntervalSince(workout.start)
            - workout.pauses.reduce(0) { $0 + $1.duration }
        #expect(Duration.seconds(active) == finished.elapsed(at: Self.at(400)))
    }

    @Test("A workout paused and resumed before goes nowhere, since its pause's times aren't kept")
    func resumedBefore() {
        let resumed = Self.started().pausing(at: Self.at(200)).resuming(at: Self.at(250))
        let finished = resumed.finishing(at: Self.at(400))
        #expect(HealthWorkout(finished: finished, pausedSince: nil) == nil)
    }

    @Test("A workout in progress gives Health nothing")
    func inProgress() {
        #expect(HealthWorkout(finished: Self.started(), pausedSince: nil) == nil)
    }
}
