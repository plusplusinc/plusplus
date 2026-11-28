import Foundation
import Testing
@testable import WorkoutStore

/// Logging sets: which set comes next, how far each row is, and what a logged set keeps.
@Suite("Workout logging")
struct WorkoutLoggingTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1000)

    private func loggedWorkout(_ workout: Workout) -> LoggedWorkout {
        LoggedWorkout(workoutID: workout.id, workoutName: "Upper", startedAt: start)
    }

    /// Logs the workout's next set, as the key does.
    private func logNext(
        _ loggedWorkout: LoggedWorkout,
        _ workout: Workout,
    ) throws -> LoggedWorkout {
        let next = try #require(workout.nextSet(after: loggedWorkout.sets))
        let row = try #require(workout.exercises.first { $0.id == next.row })
        return loggedWorkout.logging(next, of: row, at: start.addingTimeInterval(60))
    }

    @Test("Three logs on a 3-set exercise go set 2, set 3, then the next row's set 1")
    func plainRows() throws {
        let bench = try WorkoutExercise.builtIn("Barbell bench press") { $0.sets = 3 }
        let pull = try WorkoutExercise.builtIn("Pull-up")
        let workout = Workout(exercises: [bench, pull])
        var loggedWorkout = loggedWorkout(workout)
        #expect(workout.nextSet(after: loggedWorkout.sets) == PlannedSet(
            row: bench.id,
            round: 1,
            side: nil,
        ))
        loggedWorkout = try logNext(loggedWorkout, workout)
        #expect(workout.nextSet(after: loggedWorkout.sets) == PlannedSet(
            row: bench.id,
            round: 2,
            side: nil,
        ))
        loggedWorkout = try logNext(loggedWorkout, workout)
        #expect(workout.nextSet(after: loggedWorkout.sets) == PlannedSet(
            row: bench.id,
            round: 3,
            side: nil,
        ))
        loggedWorkout = try logNext(loggedWorkout, workout)
        #expect(workout.nextSet(after: loggedWorkout.sets) == PlannedSet(
            row: pull.id,
            round: 1,
            side: nil,
        ))
    }

    @Test("Logging a set already logged changes nothing")
    func logTwice() throws {
        let bench = try WorkoutExercise.builtIn("Barbell bench press") { $0.sets = 3 }
        let workout = Workout(exercises: [bench])
        let first = PlannedSet(row: bench.id, round: 1, side: nil)
        let once = loggedWorkout(workout).logging(first, of: bench, at: start)
        #expect(once.logging(first, of: bench, at: start.addingTimeInterval(5)) == once)
    }

    @Test("In a superset, a log on A1 moves to B1, then A2")
    func superset() throws {
        let superset = UUID()
        var first = try WorkoutExercise.builtIn("Push-up") { $0.sets = 3 }
        var second = try WorkoutExercise.builtIn("Pull-up") { $0.sets = 3 }
        first.supersetID = superset
        second.supersetID = superset
        let workout = Workout(exercises: [first, second])
        var loggedWorkout = loggedWorkout(workout)
        loggedWorkout = try logNext(loggedWorkout, workout)
        #expect(workout.nextSet(after: loggedWorkout.sets)?.row == second.id)
        loggedWorkout = try logNext(loggedWorkout, workout)
        #expect(workout.nextSet(after: loggedWorkout.sets) == PlannedSet(
            row: first.id,
            round: 2,
            side: nil,
        ))
    }

    @Test("A per-side set logs left then right, each its own set, and counts once both are in")
    func sides() throws {
        let row = try WorkoutExercise.builtIn("Dumbbell row") { $0.sets = 3 }
        let workout = Workout(exercises: [row])
        var loggedWorkout = loggedWorkout(workout)
        loggedWorkout = try logNext(loggedWorkout, workout)
        #expect(loggedWorkout.sets.map(\.side) == [.left])
        #expect(workout.progress(of: row.id, logged: loggedWorkout.sets)
            == RowProgress(done: 0, total: 3, sidesDone: 1))
        #expect(
            RowProgress(done: 0, total: 3, sidesDone: 1).afterSet
                == RowProgress(done: 1, total: 3, sidesDone: 0),
            "The set done, so are both its sides",
        )
        #expect(workout.isStarted(row.id, logged: loggedWorkout.sets))
        #expect(workout.nextSet(after: loggedWorkout.sets)
            == PlannedSet(row: row.id, round: 1, side: .right))
        loggedWorkout = try logNext(loggedWorkout, workout)
        #expect(loggedWorkout.sets.map(\.side) == [.left, .right])
        #expect(
            workout.progress(of: row.id, logged: loggedWorkout.sets)
                == RowProgress(done: 1, total: 3, sidesDone: 0),
            "The next set, neither side done",
        )
    }

    @Test("The key reads Log set, Log left then Log right, and Log last set on the last set")
    func logText() throws {
        let push = try WorkoutExercise.builtIn("Push-up") { $0.sets = 2 }
        let row = try WorkoutExercise.builtIn("Dumbbell row") { $0.sets = 2 }
        let workout = Workout(exercises: [push, row])
        var loggedWorkout = loggedWorkout(workout)
        var said: [String] = []
        while let next = workout.nextSet(after: loggedWorkout.sets) {
            said.append(workout.logText(for: next, after: loggedWorkout.sets))
            loggedWorkout = try logNext(loggedWorkout, workout)
        }
        // The last right side is the workout's last set, so it reads as the last, not as a side.
        #expect(said == ["Log set", "Log set", "Log left", "Log right", "Log left", "Log last set"])
        let single = Workout(exercises: [push])
        let first = PlannedSet(row: push.id, round: 1, side: nil)
        #expect(single.logText(for: first, after: []) == "Log set")
        #expect(
            single.logText(for: PlannedSet(row: push.id, round: 2, side: nil), after: [])
                == "Log set",
            "A set with an earlier one still to do is not the last",
        )
    }

    @Test("Once every set is logged there is no next set, and every row reads finished")
    func allLogged() throws {
        let row = try WorkoutExercise.builtIn("Push-up") { $0.sets = 2 }
        let workout = Workout(exercises: [row])
        var loggedWorkout = loggedWorkout(workout)
        loggedWorkout = try logNext(loggedWorkout, workout)
        loggedWorkout = try logNext(loggedWorkout, workout)
        #expect(workout.nextSet(after: loggedWorkout.sets) == nil)
        #expect(workout.progress(of: row.id, logged: loggedWorkout.sets) == RowProgress(
            done: 2,
            total: 2,
        ))
    }

    @Test("A row not started has no progress and isn't started")
    func notStarted() throws {
        let row = try WorkoutExercise.builtIn("Push-up") { $0.sets = 2 }
        let workout = Workout(exercises: [row])
        #expect(workout.progress(of: row.id, logged: []) == RowProgress(done: 0, total: 2))
        #expect(!workout.isStarted(row.id, logged: []))
    }

    @Test("Raising a finished row's sets brings the next set back to it")
    func raisedSets() throws {
        let first = try WorkoutExercise.builtIn("Push-up") { $0.sets = 1 }
        let second = try WorkoutExercise.builtIn("Pull-up")
        var workout = Workout(exercises: [first, second])
        let loggedWorkout = try logNext(loggedWorkout(workout), workout)
        #expect(workout.nextSet(after: loggedWorkout.sets)?.row == second.id)
        workout.exercises[0].plan.sets = 2
        #expect(workout.nextSet(after: loggedWorkout.sets) == PlannedSet(
            row: first.id,
            round: 2,
            side: nil,
        ))
    }

    @Test("A log after a plan change records the new numbers, as done and as planned")
    func changedPlan() throws {
        var row = try WorkoutExercise.builtIn("Barbell bench press")
        row.plan.weight = Weight(135, .pounds)
        row.plan.target = .reps(8)
        var workout = Workout(exercises: [row])
        var loggedWorkout = loggedWorkout(workout)
        loggedWorkout = try logNext(loggedWorkout, workout)
        workout.exercises[0].plan.weight = Weight(145, .pounds)
        loggedWorkout = try logNext(loggedWorkout, workout)
        #expect(loggedWorkout.sets.map(\.weight) == [Weight(135, .pounds), Weight(145, .pounds)])
        #expect(loggedWorkout.sets.map(\.plannedWeight) == [
            Weight(135, .pounds),
            Weight(145, .pounds),
        ])
        #expect(loggedWorkout.sets.map(\.target) == [.reps(8), .reps(8)])
        #expect(loggedWorkout.sets[0].exerciseID == row.exercise.id)
    }

    @Test("An exercise with no load logs no weight")
    func noLoad() throws {
        let row = try WorkoutExercise.builtIn("Push-up")
        let workout = Workout(exercises: [row])
        let loggedWorkout = try logNext(loggedWorkout(workout), workout)
        #expect(loggedWorkout.sets.first?.weight == nil)
        #expect(loggedWorkout.sets.first?.plannedWeight == nil)
    }
}
