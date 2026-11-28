import Foundation
import Testing
@testable import WorkoutStore

/// What a finished workout gives Apple Health: its start, end, and pauses, only when its length
/// there equals its time in the app, and its type as kept at Finish.
@Suite("Health workout")
struct HealthWorkoutTests {
    private static func at(_ seconds: Double) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    private static func started() -> WorkoutSession {
        WorkoutSession(workoutID: UUID(), workoutName: "Upper", startedAt: at(100))
    }

    /// Health's length for `workout`: start to end, its pauses left out.
    private static func length(_ workout: HealthWorkout) -> Duration {
        .seconds(workout.end.timeIntervalSince(workout.start)
            - workout.pauses.reduce(0) { $0 + $1.duration })
    }

    @Test(
        "A workout finished in the app goes with each pause, its length the app's time",
        arguments: [
            // Never paused.
            [],
            // Finished while paused.
            [(300.0, nil)],
            // Paused and resumed once.
            [(200, 250)],
            // Paused and resumed twice, then finished while paused.
            [(150, 160), (200, 250), (300, nil)],
        ] as [[(Double, Double?)]],
    )
    func pausesKept(pauses: [(Double, Double?)]) throws {
        var logged = Self.started()
        for (start, end) in pauses {
            logged = logged.pausing(at: Self.at(start))
            if let end {
                logged = logged.resuming(at: Self.at(end))
            }
        }
        let finished = logged.finishing(at: Self.at(400))
        let workout = try HealthWorkout(finished, in: .builtIn)
        #expect(workout.id == finished.id)
        #expect(workout.start == Self.at(100))
        #expect(workout.end == Self.at(400))
        #expect(workout.pauses == pauses.map { start, end in
            DateInterval(start: Self.at(start), end: Self.at(end ?? 400))
        })
        #expect(Self.length(workout) == finished.elapsed(at: Self.at(400)))
    }

    @Test(
        "A workout whose pauses don't account for its time paused goes nowhere",
        arguments: [
            // Paused before the store kept times: its length alone.
            (30.0, []),
            // Times that don't add up to the time paused.
            (30, [(200, 210)]),
            // A pause before the start.
            (10, [(90, 100)]),
            // A pause past the end.
            (20, [(390, 410)]),
            // Out of order.
            (20, [(300, 310), (200, 210)]),
        ] as [(Double, [(Double, Double)])],
    )
    func timesNotKept(pausedSeconds: Double, pauses: [(Double, Double)]) {
        let finished = WorkoutSession(
            workoutID: UUID(),
            workoutName: "Upper",
            startedAt: Self.at(100),
            pausedSeconds: pausedSeconds,
            pauses: pauses.map { DateInterval(start: Self.at($0), end: Self.at($1)) },
            endedAt: Self.at(400),
        )
        #expect(throws: HealthWorkout.Withheld.timesNotKept) {
            try HealthWorkout(finished, in: .builtIn)
        }
    }

    @Test(
        "A workout ending at or before its start, as with a clock set back, goes nowhere",
        arguments: [90.0, 100],
    )
    func endNotAfterStart(end: Double) {
        let finished = WorkoutSession(
            workoutID: UUID(),
            workoutName: "Upper",
            startedAt: Self.at(100),
            endedAt: Self.at(end),
        )
        #expect(throws: HealthWorkout.Withheld.noLength) {
            try HealthWorkout(finished, in: .builtIn)
        }
    }

    @Test("A workout in progress gives Health nothing, for that reason")
    func inProgress() {
        #expect(throws: HealthWorkout.Withheld.notFinished) {
            try HealthWorkout(Self.started(), in: .builtIn)
        }
    }

    @Test("The type kept at Finish wins over the exercises as they are now")
    func storedTypeWins() throws {
        let row = try WorkoutExercise.builtIn("Hamstring stretch")
        var finished = Self.started()
            .logging(PlannedSet(row: row.id, round: 1, side: nil), of: row, at: Self.at(200))
            .finishing(at: Self.at(400))
        #expect(try HealthWorkout(finished, in: .builtIn).activity == .flexibility)
        finished.healthActivity = .traditionalStrength
        #expect(try HealthWorkout(finished, in: .builtIn).activity == .traditionalStrength)
    }
}
