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

    /// The workout for `before` finished at `end`, as Finish makes it.
    private static func finish(
        _ before: LoggedWorkout,
        at end: Double,
    ) throws(HealthWorkout.Withheld) -> HealthWorkout {
        try HealthWorkout(
            finished: before.finishing(at: at(end)),
            in: .builtIn,
            resumedSeconds: before.pausedSeconds,
            pausedSince: before.pausedAt,
        )
    }

    @Test("A workout never paused goes with its start and end, and no pauses")
    func neverPaused() throws {
        let before = Self.started()
        let workout = try Self.finish(before, at: 400)
        #expect(workout.id == before.id)
        #expect(workout.start == Self.at(100))
        #expect(workout.end == Self.at(400))
        #expect(workout.pauses.isEmpty)
    }

    @Test("A workout finished while paused goes with that pause, its length leaving it out")
    func finishedWhilePaused() throws {
        let paused = Self.started().pausing(at: Self.at(300))
        let workout = try Self.finish(paused, at: 400)
        #expect(workout.pauses == [DateInterval(start: Self.at(300), end: Self.at(400))])
        let active = workout.end.timeIntervalSince(workout.start)
            - workout.pauses.reduce(0) { $0 + $1.duration }
        let finished = paused.finishing(at: Self.at(400))
        #expect(Duration.seconds(active) == finished.elapsed(at: Self.at(400)))
    }

    @Test("A workout paused and resumed before goes nowhere, paused again at its finish or not")
    func resumedBefore() {
        let resumed = Self.started().pausing(at: Self.at(200)).resuming(at: Self.at(250))
        #expect(throws: HealthWorkout.Withheld.resumedBefore) {
            try Self.finish(resumed, at: 400)
        }
        #expect(throws: HealthWorkout.Withheld.resumedBefore) {
            try Self.finish(resumed.pausing(at: Self.at(300)), at: 400)
        }
    }

    @Test("A workout in progress gives Health nothing, for that reason")
    func inProgress() {
        #expect(throws: HealthWorkout.Withheld.notFinished) {
            try HealthWorkout(
                finished: Self.started(),
                in: .builtIn,
                resumedSeconds: 0,
                pausedSince: nil,
            )
        }
    }
}
