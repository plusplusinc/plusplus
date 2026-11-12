import Foundation
import Testing
@testable import WorkoutStore

/// A workout in progress on its routine: where it is, which rows show what, and what a log leads
/// to.
@Suite("Live workout")
struct LiveWorkoutTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1000)

    private func live(_ routine: Routine) -> LiveWorkout {
        LiveWorkout(
            routine: routine,
            workout: Workout(routineID: routine.id, routineName: "Upper", startedAt: start),
        )
    }

    /// The workout with `sets` logged, in order, at their rows' plans.
    private func logging(_ sets: [PlannedSet], on live: LiveWorkout) throws -> LiveWorkout {
        var logged = live
        for set in sets {
            let row = try #require(live.routine.exercises.first { $0.id == set.row })
            logged.workout = logged.workout.logging(set, of: row, at: start)
        }
        return logged
    }

    private func superset(_ first: String, _ second: String, sets: Int) throws -> Routine {
        let id = UUID()
        var memberA = try RoutineExercise.builtIn(first) { $0.sets = sets }
        var memberB = try RoutineExercise.builtIn(second) { $0.sets = sets }
        memberA.supersetID = id
        memberB.supersetID = id
        return Routine(exercises: [memberA, memberB])
    }

    @Test("The current set and exercise are the first set not logged, and its row")
    func current() throws {
        let push = try RoutineExercise.builtIn("Push-up") { $0.sets = 2 }
        let pull = try RoutineExercise.builtIn("Pull-up")
        let routine = Routine(exercises: [push, pull])
        var live = live(routine)
        #expect(live.currentSet == PlannedSet(row: push.id, round: 1))
        #expect(live.currentExercise?.id == push.id)
        live = try logging(
            [PlannedSet(row: push.id, round: 1), PlannedSet(row: push.id, round: 2)],
            on: live,
        )
        #expect(live.currentSet == PlannedSet(row: pull.id, round: 1))
        #expect(live.currentExercise?.id == pull.id)
    }

    @Test("A workout on a routine with no exercises is not done; one with every set logged is")
    func done() throws {
        let empty = live(Routine())
        #expect(empty.currentSet == nil)
        #expect(!empty.isDone)
        let push = try RoutineExercise.builtIn("Push-up") { $0.sets = 1 }
        let one = live(Routine(exercises: [push]))
        #expect(!one.isDone)
        #expect(try logging([PlannedSet(row: push.id, round: 1)], on: one).isDone)
    }

    @Test("A row is finished once every set of it is logged, and never with none planned")
    func finished() throws {
        let push = try RoutineExercise.builtIn("Push-up") { $0.sets = 2 }
        let pull = try RoutineExercise.builtIn("Pull-up") { $0.sets = 0 }
        let routine = Routine(exercises: [push, pull])
        var live = live(routine)
        #expect(live.finishedRows.isEmpty)
        live = try logging([PlannedSet(row: push.id, round: 1)], on: live)
        #expect(live.finishedRows.isEmpty)
        live = try logging([PlannedSet(row: push.id, round: 2)], on: live)
        #expect(live.finishedRows == [push.id])
    }

    @Test("The current row shows its bars from its first set")
    func currentBars() throws {
        let push = try RoutineExercise.builtIn("Push-up") { $0.sets = 3 }
        let live = live(Routine(exercises: [push]))
        let bars = try #require(live.bars(of: push.id))
        #expect(bars == (0, 3))
    }

    @Test("A row not started shows no bars")
    func notStartedBars() throws {
        let push = try RoutineExercise.builtIn("Push-up") { $0.sets = 3 }
        let pull = try RoutineExercise.builtIn("Pull-up")
        let live = live(Routine(exercises: [push, pull]))
        #expect(live.bars(of: pull.id) == nil)
    }

    @Test("A superset member started and not current shows its bars")
    func startedBars() throws {
        let routine = try superset("Push-up", "Pull-up", sets: 3)
        let (rowA, rowB) = (routine.exercises[0].id, routine.exercises[1].id)
        let live = try logging(
            [PlannedSet(row: rowA, round: 1), PlannedSet(row: rowB, round: 1)],
            on: live(routine),
        )
        #expect(live.currentExercise?.id == rowA)
        let bars = try #require(live.bars(of: rowB))
        #expect(bars == (1, 3))
    }

    @Test("A finished row shows no bars")
    func finishedBars() throws {
        let push = try RoutineExercise.builtIn("Push-up") { $0.sets = 1 }
        let pull = try RoutineExercise.builtIn("Pull-up")
        let live = try logging(
            [PlannedSet(row: push.id, round: 1)],
            on: live(Routine(exercises: [push, pull])),
        )
        #expect(live.finishedRows == [push.id])
        #expect(live.bars(of: push.id) == nil)
    }

    @Test("A log with more sets on the exercise leads to the next set")
    func nextSet() throws {
        let push = try RoutineExercise.builtIn("Push-up") { $0.sets = 2 }
        let row = try RoutineExercise.builtIn("Dumbbell row") { $0.sets = 1 }
        let live = live(Routine(exercises: [push, row]))
        #expect(live.step(logging: PlannedSet(row: push.id, round: 1)) == .nextSet)
        let pushed = try logging(
            [PlannedSet(row: push.id, round: 1), PlannedSet(row: push.id, round: 2)],
            on: live,
        )
        let left = PlannedSet(row: row.id, round: 1, side: .left)
        #expect(pushed.currentSet == left)
        #expect(pushed.step(logging: left) == .nextSet, "Left leads to right")
    }

    @Test("A log on an exercise's last set leads down to the next exercise")
    func down() throws {
        let push = try RoutineExercise.builtIn("Push-up") { $0.sets = 1 }
        let pull = try RoutineExercise.builtIn("Pull-up")
        let live = live(Routine(exercises: [push, pull]))
        #expect(live.step(logging: PlannedSet(row: push.id, round: 1)) == .nextExercise(
            to: PlannedSet(row: pull.id, round: 1),
            isBack: false,
            startsRound: false,
        ))
    }

    @Test("In a superset, B's set leads back to A in the next round")
    func round() throws {
        let routine = try superset("Push-up", "Pull-up", sets: 3)
        let (rowA, rowB) = (routine.exercises[0].id, routine.exercises[1].id)
        let live = try logging([PlannedSet(row: rowA, round: 1)], on: live(routine))
        #expect(live.step(logging: PlannedSet(row: rowB, round: 1)) == .nextExercise(
            to: PlannedSet(row: rowA, round: 2),
            isBack: true,
            startsRound: true,
        ))
    }

    @Test("Back to an unfinished plain row above starts no round")
    func backToPlainRow() throws {
        let push = try RoutineExercise.builtIn("Push-up") { $0.sets = 2 }
        let pull = try RoutineExercise.builtIn("Pull-up") { $0.sets = 2 }
        // Pull-up's first set logged while it was first, then the rows swapped.
        let live = try logging(
            [PlannedSet(row: pull.id, round: 1)],
            on: live(Routine(exercises: [push, pull])),
        )
        #expect(live.step(logging: PlannedSet(row: pull.id, round: 2)) == .nextExercise(
            to: PlannedSet(row: push.id, round: 1),
            isBack: true,
            startsRound: false,
        ))
    }

    @Test("The last planned set leads nowhere")
    func last() throws {
        let push = try RoutineExercise.builtIn("Push-up") { $0.sets = 2 }
        let live = try logging([PlannedSet(row: push.id, round: 1)], on: live(Routine(
            exercises: [push],
        )))
        #expect(live.step(logging: PlannedSet(row: push.id, round: 2)) == .last)
    }

    @Test("Hiding the newest logged set gives the workout before it, and no older set")
    func hiding() throws {
        let push = try RoutineExercise.builtIn("Push-up") { $0.sets = 3 }
        let routine = Routine(exercises: [push])
        let (first, second) = (
            PlannedSet(row: push.id, round: 1),
            PlannedSet(row: push.id, round: 2),
        )
        let before = try logging([first], on: live(routine))
        let after = try logging([second], on: before)
        let hidden = after.hiding([second])
        #expect(hidden == before)
        #expect(hidden.currentSet == second)
        #expect(hidden.logText == "Log set")
        let bars = try #require(hidden.bars(of: push.id))
        #expect(bars == (1, 3))
        #expect(after.hiding([first]) == after, "A set logged before the newest stays shown")
        #expect(after.hiding([]) == after)
    }

    @Test("The key's words come from the pair")
    func logText() throws {
        let push = try RoutineExercise.builtIn("Push-up") { $0.sets = 2 }
        var live = live(Routine(exercises: [push]))
        #expect(live.logText == "Log set")
        live = try logging([PlannedSet(row: push.id, round: 1)], on: live)
        #expect(live.logText == "Log last set")
        live = try logging([PlannedSet(row: push.id, round: 2)], on: live)
        #expect(live.logText == nil)
    }
}
