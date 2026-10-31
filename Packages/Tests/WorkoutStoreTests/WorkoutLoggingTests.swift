import Foundation
import Testing
@testable import WorkoutStore

/// Logging sets: which set comes next, how far each row is, and what a logged set keeps.
@Suite("Workout logging")
struct WorkoutLoggingTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1000)

    private func workout(_ routine: Routine) -> Workout {
        Workout(routineID: routine.id, routineName: "Upper", startedAt: start)
    }

    /// Logs the routine's next set, as the key does.
    private func logNext(_ workout: Workout, _ routine: Routine) throws -> Workout {
        let next = try #require(routine.nextSet(after: workout.sets))
        let row = try #require(routine.exercises.first { $0.id == next.row })
        return workout.logging(next, of: row, at: start.addingTimeInterval(60))
    }

    @Test("Three logs on a 3-set exercise go set 2, set 3, then the next row's set 1")
    func plainRows() throws {
        let bench = try RoutineExercise.builtIn("Barbell bench press") { $0.sets = 3 }
        let pull = try RoutineExercise.builtIn("Pull-up")
        let routine = Routine(exercises: [bench, pull])
        var workout = workout(routine)
        #expect(routine.nextSet(after: workout.sets) == PlannedSet(row: bench.id, round: 1))
        workout = try logNext(workout, routine)
        #expect(routine.nextSet(after: workout.sets) == PlannedSet(row: bench.id, round: 2))
        workout = try logNext(workout, routine)
        #expect(routine.nextSet(after: workout.sets) == PlannedSet(row: bench.id, round: 3))
        workout = try logNext(workout, routine)
        #expect(routine.nextSet(after: workout.sets) == PlannedSet(row: pull.id, round: 1))
    }

    @Test("Logging a set already logged changes nothing")
    func logTwice() throws {
        let bench = try RoutineExercise.builtIn("Barbell bench press") { $0.sets = 3 }
        let routine = Routine(exercises: [bench])
        let first = PlannedSet(row: bench.id, round: 1)
        let once = workout(routine).logging(first, of: bench, at: start)
        #expect(once.logging(first, of: bench, at: start.addingTimeInterval(5)) == once)
    }

    @Test("In a superset, a log on A1 moves to B1, then A2")
    func superset() throws {
        let superset = UUID()
        var first = try RoutineExercise.builtIn("Push-up") { $0.sets = 3 }
        var second = try RoutineExercise.builtIn("Pull-up") { $0.sets = 3 }
        first.supersetID = superset
        second.supersetID = superset
        let routine = Routine(exercises: [first, second])
        var workout = workout(routine)
        workout = try logNext(workout, routine)
        #expect(routine.nextSet(after: workout.sets)?.row == second.id)
        workout = try logNext(workout, routine)
        #expect(routine.nextSet(after: workout.sets) == PlannedSet(row: first.id, round: 2))
    }

    @Test("A per-side set logs left then right, each its own set, and counts once both are in")
    func sides() throws {
        let row = try RoutineExercise.builtIn("Dumbbell row") { $0.sets = 3 }
        let routine = Routine(exercises: [row])
        var workout = workout(routine)
        workout = try logNext(workout, routine)
        #expect(workout.sets.map(\.side) == [.left])
        #expect(routine.progress(of: row.id, logged: workout.sets) == (0, 3))
        #expect(routine.isStarted(row.id, logged: workout.sets))
        #expect(routine.nextSet(after: workout.sets)
            == PlannedSet(row: row.id, round: 1, side: .right))
        workout = try logNext(workout, routine)
        #expect(workout.sets.map(\.side) == [.left, .right])
        #expect(routine.progress(of: row.id, logged: workout.sets) == (1, 3))
    }

    @Test("The key reads Log set on a whole set, Log left then Log right on a side, and Log last set on the workout's last")
    func logText() throws {
        let push = try RoutineExercise.builtIn("Push-up") { $0.sets = 2 }
        let row = try RoutineExercise.builtIn("Dumbbell row") { $0.sets = 1 }
        let routine = Routine(exercises: [push, row])
        var workout = workout(routine)
        var said: [String] = []
        while let next = routine.nextSet(after: workout.sets) {
            said.append(routine.logText(for: next, after: workout.sets))
            workout = try logNext(workout, routine)
        }
        // The right side is the workout's last set, so it reads as the last, not as a side.
        #expect(said == ["Log set", "Log set", "Log left", "Log last set"])
        let single = Routine(exercises: [push])
        let first = PlannedSet(row: push.id, round: 1)
        #expect(single.logText(for: first, after: []) == "Log set")
        #expect(single.logText(for: PlannedSet(row: push.id, round: 2), after: [])
            == "Log set", "A set with an earlier one still to do is not the last")
    }

    @Test("Once every set is logged there is no next set, and every row reads finished")
    func allLogged() throws {
        let row = try RoutineExercise.builtIn("Push-up") { $0.sets = 2 }
        let routine = Routine(exercises: [row])
        var workout = workout(routine)
        workout = try logNext(workout, routine)
        workout = try logNext(workout, routine)
        #expect(routine.nextSet(after: workout.sets) == nil)
        #expect(routine.progress(of: row.id, logged: workout.sets) == (2, 2))
    }

    @Test("A row not started has no progress and isn't started")
    func notStarted() throws {
        let row = try RoutineExercise.builtIn("Push-up") { $0.sets = 2 }
        let routine = Routine(exercises: [row])
        #expect(routine.progress(of: row.id, logged: []) == (0, 2))
        #expect(!routine.isStarted(row.id, logged: []))
    }

    @Test("Raising a finished row's sets brings the next set back to it")
    func raisedSets() throws {
        let first = try RoutineExercise.builtIn("Push-up") { $0.sets = 1 }
        let second = try RoutineExercise.builtIn("Pull-up")
        var routine = Routine(exercises: [first, second])
        let workout = try logNext(workout(routine), routine)
        #expect(routine.nextSet(after: workout.sets)?.row == second.id)
        routine.exercises[0].plan.sets = 2
        #expect(routine.nextSet(after: workout.sets) == PlannedSet(row: first.id, round: 2))
    }

    @Test("A log after a plan change records the new numbers, as done and as planned")
    func changedPlan() throws {
        var row = try RoutineExercise.builtIn("Barbell bench press")
        row.plan.weight = Weight(135, .pounds)
        row.plan.target = .reps(8)
        var routine = Routine(exercises: [row])
        var workout = workout(routine)
        workout = try logNext(workout, routine)
        routine.exercises[0].plan.weight = Weight(145, .pounds)
        workout = try logNext(workout, routine)
        #expect(workout.sets.map(\.weight) == [Weight(135, .pounds), Weight(145, .pounds)])
        #expect(workout.sets.map(\.plannedWeight) == [Weight(135, .pounds), Weight(145, .pounds)])
        #expect(workout.sets.map(\.target) == [.reps(8), .reps(8)])
        #expect(workout.sets[0].exerciseID == row.exercise.id)
    }

    @Test("An exercise with no load logs no weight")
    func noLoad() throws {
        let row = try RoutineExercise.builtIn("Push-up")
        let routine = Routine(exercises: [row])
        let workout = try logNext(workout(routine), routine)
        #expect(workout.sets.first?.weight == nil)
        #expect(workout.sets.first?.plannedWeight == nil)
    }
}
