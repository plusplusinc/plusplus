import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

/// A created exercise changed or deleted after routines use it. A relaunch is a second store
/// over the same container: it sees only what was saved.
@Suite("Routine store, customizing and deleting an exercise")
struct RoutineStoreCustomizeTests {
    private let container: ModelContainer

    init() throws {
        container = try WorkoutStoreContainer.make(mode: .inMemory, schema: RoutineStore.schema)
    }

    private func relaunch() -> RoutineStore {
        RoutineStore(modelContainer: container)
    }

    private static func at(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    private static let curl = CreatedExercise(
        name: "Cable curl",
        muscleGroups: [.arms],
        equipment: [.dumbbells],
    )

    /// A row of `created` at 4 × 8, 30 lb, its rest automatic.
    private static func row(of created: CreatedExercise) -> RoutineExercise {
        var row = RoutineExercise(exercise: Exercise(created: created), weightUnit: .pounds)
        row.plan.sets = 4
        row.plan.target = .reps(8)
        row.plan.weight = Weight(30, .pounds)
        return row
    }

    /// The routine `id` as a relaunch reads it.
    private func reread(_ id: Routine.ID) async throws -> Routine {
        try #require(try await relaunch().routine(id, weightUnit: .pounds))
    }

    /// Every workout stored, as a relaunch would read it.
    private func workouts() throws -> [Workout] {
        try ModelContext(container).fetch(FetchDescriptor<StoredWorkout>()).map(\.workout)
    }

    @Test("A new muscle group reaches every routine's row, its numbers kept, its rest following")
    func groupsReachRows() async throws {
        let store = relaunch()
        try await store.save(Self.curl)
        let row = Self.row(of: Self.curl)
        let routines = [Routine(name: "A", exercises: [row]), Routine(name: "B", exercises: [row])]
        for routine in routines {
            try await store.save(routine)
        }
        // Arms, single-joint: 60 s at 8 reps.
        #expect(try await reread(routines[0].id).exercises.first?.rest == 60)

        var shoulders = Self.curl
        shoulders.muscleGroups = [.shoulders]
        try await relaunch().save(shoulders)
        for routine in routines {
            let reread = try await reread(routine.id).exercises.first
            #expect(reread?.exercise.muscleGroups == [.shoulders])
            #expect(reread?.plan.sets == 4)
            #expect(reread?.plan.target == .reps(8))
            #expect(reread?.plan.weight == Weight(30, .pounds))
            // Shoulders, upper-body compound: 90 s at 8 reps.
            #expect(reread?.rest == 90)
        }
    }

    @Test("A rename reaches every routine; a set logged before keeps the old name")
    func renameKeepsLoggedName() async throws {
        let store = relaunch()
        try await store.save(Self.curl)
        let routine = Routine(name: "Arms", exercises: [Self.row(of: Self.curl)])
        try await store.save(routine)
        var workout = Workout(routineID: routine.id, routineName: "Arms", startedAt: Self.at(10))
        let next = try #require(routine.nextSet(after: workout.sets))
        workout = workout.logging(next, of: routine.exercises[0], at: Self.at(20))
        try await store.save(workout)

        var renamed = Self.curl
        renamed.name = "Hammer curl"
        try await relaunch().save(renamed)
        #expect(try await reread(routine.id).exercises.map(\.exercise.name) == ["Hammer curl"])
        #expect(try await relaunch().exercises().exercise(id: Self.curl.id)?.name == "Hammer curl")
        let set = try #require(try workouts().first?.sets.first)
        #expect(set.exerciseID == Self.curl.id)
        #expect(set.exerciseName == "Cable curl")
    }

    @Test("Switching Measure, or the weight, away and back brings every row's numbers back")
    func measureRoundTrip() async throws {
        let store = relaunch()
        try await store.save(Self.curl)
        let routine = Routine(name: "Arms", exercises: [Self.row(of: Self.curl)])
        try await store.save(routine)

        var timed = Self.curl
        timed.measure = .time
        timed.equipment = []
        try await relaunch().save(timed)
        var edited = try await reread(routine.id)
        #expect(edited.exercises[0].plan.target == .time(seconds: 30))
        #expect(edited.exercises[0].plan.weight == nil)
        // Saved while timed and bodyweight: the reps and the weight stay stored.
        edited.exercises[0].plan.target = .time(seconds: 45)
        try await relaunch().save(edited)

        try await relaunch().save(Self.curl)
        let back = try await reread(routine.id).exercises[0].plan
        #expect(back.target == .reps(8))
        #expect(back.weight == Weight(30, .pounds))
        #expect(back.sets == 4)
        try await relaunch().save(timed)
        #expect(try await reread(routine.id).exercises[0].plan.target == .time(seconds: 45))
    }

    @Test("A delete takes the exercise out of the list and every routine; logged sets still read")
    func delete() async throws {
        let store = relaunch()
        try await store.save(Self.curl)
        let pushUp = try RoutineExercise.builtIn("Push-up")
        let named = Routine(name: "Arms", exercises: [Self.row(of: Self.curl), pushUp])
        let unnamed = Routine(exercises: [Self.row(of: Self.curl)])
        let emptiedNamed = Routine(name: "Curls", exercises: [Self.row(of: Self.curl)])
        for (index, routine) in [named, unnamed, emptiedNamed].enumerated() {
            try await store.save(routine, at: Self.at(TimeInterval(index)))
        }
        var workout = Workout(routineID: named.id, routineName: "Arms", startedAt: Self.at(10))
        let next = try #require(named.nextSet(after: workout.sets))
        workout = workout.logging(next, of: named.exercises[0], at: Self.at(20))
        try await store.save(workout)

        try await relaunch().deleteExercise(Self.curl.id)
        #expect(try await relaunch().exercises() == .builtIn)
        #expect(try await reread(named.id).exercises == [pushUp])
        // Left with nothing, no name and no rows, it goes, as a cleared one does.
        #expect(try await relaunch().routine(unnamed.id, weightUnit: .pounds) == nil)
        // A name is something: it stays, with no rows.
        #expect(try await reread(emptiedNamed.id).exercises.isEmpty)
        let set = try #require(try workouts().first?.sets.first)
        #expect(set.exerciseID == Self.curl.id)
        #expect(set.exerciseName == "Cable curl")
    }

    @Test("Reading one routine doesn't mark it opened")
    func readDoesNotOpen() async throws {
        let store = relaunch()
        let older = try Routine(name: "Older", exercises: [RoutineExercise.builtIn("Push-up")])
        let newer = try Routine(name: "Newer", exercises: [RoutineExercise.builtIn("Pull-up")])
        try await store.save(older, at: Self.at(1))
        try await store.save(newer, at: Self.at(2))
        #expect(try await relaunch().routine(older.id, weightUnit: .pounds) == older)
        #expect(try await relaunch().routinesByRecency(weightUnit: .pounds).map(\.name)
            == ["Newer", "Older"])
    }
}
