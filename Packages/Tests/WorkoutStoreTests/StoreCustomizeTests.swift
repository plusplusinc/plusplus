import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

/// A created exercise changed or deleted after workouts use it. A relaunch is a second store
/// over the same container: it sees only what was saved.
@Suite("Workout store, customizing and deleting an exercise")
struct StoreCustomizeTests {
    private let container: ModelContainer

    init() throws {
        container = try WorkoutStoreContainer.make(mode: .inMemory, schema: Store.schema)
    }

    private func relaunch() -> Store {
        Store(modelContainer: container)
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
    private static func row(of created: CreatedExercise) -> WorkoutExercise {
        var row = WorkoutExercise(exercise: Exercise(created: created), weightUnit: .pounds)
        row.plan.sets = 4
        row.plan.target = .reps(8)
        row.plan.weight = Weight(30, .pounds)
        return row
    }

    /// The workout `id` as a relaunch reads it.
    private func reread(_ id: Workout.ID) async throws -> Workout {
        try #require(try await relaunch().workout(id, weightUnit: .pounds))
    }

    /// Every workout stored, as a relaunch would read it.
    private func workoutSessions() throws -> [WorkoutSession] {
        try ModelContext(container).fetch(FetchDescriptor<StoredWorkoutSession>())
            .map(\.workoutSession)
    }

    @Test("A new muscle group reaches every workout's row, its numbers kept, its rest following")
    func groupsReachRows() async throws {
        let store = relaunch()
        try await store.save(Self.curl)
        let row = Self.row(of: Self.curl)
        let workouts = [Workout(name: "A", exercises: [row]), Workout(name: "B", exercises: [row])]
        for workout in workouts {
            try await store.save(workout)
        }
        // Arms, single-joint: 60 s at 8 reps.
        #expect(try await reread(workouts[0].id).exercises.first?.rest == 60)

        var shoulders = Self.curl
        shoulders.muscleGroups = [.shoulders]
        try await relaunch().save(shoulders)
        for workout in workouts {
            let reread = try await reread(workout.id).exercises.first
            #expect(reread?.exercise.muscleGroups == [.shoulders])
            #expect(reread?.plan.sets == 4)
            #expect(reread?.plan.target == .reps(8))
            #expect(reread?.plan.weight == Weight(30, .pounds))
            // Shoulders, upper-body compound: 90 s at 8 reps.
            #expect(reread?.rest == 90)
        }
    }

    @Test("A rename reaches every workout; a set logged before keeps the old name")
    func renameKeepsLoggedName() async throws {
        let store = relaunch()
        try await store.save(Self.curl)
        let workout = Workout(name: "Arms", exercises: [Self.row(of: Self.curl)])
        try await store.save(workout)
        var workoutSession = WorkoutSession(
            workoutID: workout.id,
            workoutName: "Arms",
            startedAt: Self.at(10),
        )
        let next = try #require(workout.nextSet(after: workoutSession.sets))
        workoutSession = workoutSession.logging(next, of: workout.exercises[0], at: Self.at(20))
        try await store.save(workoutSession)

        var renamed = Self.curl
        renamed.name = "Hammer curl"
        try await relaunch().save(renamed)
        #expect(try await reread(workout.id).exercises.map(\.exercise.name) == ["Hammer curl"])
        #expect(try await relaunch().exercises().exercise(id: Self.curl.id)?.name == "Hammer curl")
        let set = try #require(try workoutSessions().first?.sets.first)
        #expect(set.exerciseID == Self.curl.id)
        #expect(set.exerciseName == "Cable curl")
    }

    @Test("A rename gives a set logged with no name, before names were kept, the old one")
    func renameFillsUnnamedSet() async throws {
        let store = relaunch()
        try await store.save(Self.curl)
        let workout = Workout(name: "Arms", exercises: [Self.row(of: Self.curl)])
        try await store.save(workout)
        var workoutSession = WorkoutSession(
            workoutID: workout.id,
            workoutName: "Arms",
            startedAt: Self.at(10),
        )
        let next = try #require(workout.nextSet(after: workoutSession.sets))
        workoutSession = workoutSession.logging(next, of: workout.exercises[0], at: Self.at(20))
        try await store.save(workoutSession)
        let context = ModelContext(container)
        let set = try #require(try context.fetch(FetchDescriptor<StoredLoggedSet>()).first)
        set.exerciseName = nil
        try context.save()

        var renamed = Self.curl
        renamed.name = "Hammer curl"
        try await relaunch().save(renamed)
        #expect(try workoutSessions().first?.sets.first?.exerciseName == "Cable curl")
    }

    @Test("Switching Measure, or the weight, away and back brings every row's numbers back")
    func measureRoundTrip() async throws {
        let store = relaunch()
        try await store.save(Self.curl)
        let workout = Workout(name: "Arms", exercises: [Self.row(of: Self.curl)])
        try await store.save(workout)

        var timed = Self.curl
        timed.measure = .time
        timed.equipment = []
        try await relaunch().save(timed)
        var edited = try await reread(workout.id)
        #expect(edited.exercises[0].plan.target == .time(seconds: 30))
        #expect(edited.exercises[0].plan.weight == nil)
        // Saved while timed and bodyweight: the reps and the weight stay stored.
        edited.exercises[0].plan.target = .time(seconds: 45)
        try await relaunch().save(edited)

        try await relaunch().save(Self.curl)
        let back = try await reread(workout.id).exercises[0].plan
        #expect(back.target == .reps(8))
        #expect(back.weight == Weight(30, .pounds))
        #expect(back.sets == 4)
        try await relaunch().save(timed)
        #expect(try await reread(workout.id).exercises[0].plan.target == .time(seconds: 45))
    }

    @Test("A delete takes the exercise out of the list and every workout; logged sets still read")
    func delete() async throws {
        let store = relaunch()
        try await store.save(Self.curl)
        let pushUp = try WorkoutExercise.builtIn("Push-up")
        let named = Workout(name: "Arms", exercises: [Self.row(of: Self.curl), pushUp])
        let unnamed = Workout(exercises: [Self.row(of: Self.curl)])
        let emptiedNamed = Workout(name: "Curls", exercises: [Self.row(of: Self.curl)])
        for (index, workout) in [named, unnamed, emptiedNamed].enumerated() {
            try await store.save(workout, at: Self.at(TimeInterval(index)))
        }
        var workoutSession = WorkoutSession(
            workoutID: named.id,
            workoutName: "Arms",
            startedAt: Self.at(10),
        )
        let next = try #require(named.nextSet(after: workoutSession.sets))
        workoutSession = workoutSession.logging(next, of: named.exercises[0], at: Self.at(20))
        try await store.save(workoutSession)

        try await relaunch().deleteExercise(Self.curl.id)
        #expect(try await relaunch().exercises() == .builtIn)
        #expect(try await reread(named.id).exercises == [pushUp])
        // Left with nothing, no name and no rows, it goes, as a cleared one does.
        #expect(try await relaunch().workout(unnamed.id, weightUnit: .pounds) == nil)
        // A name is something: it stays, with no rows.
        #expect(try await reread(emptiedNamed.id).exercises.isEmpty)
        let set = try #require(try workoutSessions().first?.sets.first)
        #expect(set.exerciseID == Self.curl.id)
        #expect(set.exerciseName == "Cable curl")
    }

    @Test("Reading one workout doesn't mark it opened")
    func readDoesNotOpen() async throws {
        let store = relaunch()
        let older = try Workout(name: "Older", exercises: [WorkoutExercise.builtIn("Push-up")])
        let newer = try Workout(name: "Newer", exercises: [WorkoutExercise.builtIn("Pull-up")])
        try await store.save(older, at: Self.at(1))
        try await store.save(newer, at: Self.at(2))
        #expect(try await relaunch().workout(older.id, weightUnit: .pounds) == older)
        #expect(try await relaunch().workoutsByRecency(weightUnit: .pounds).map(\.name)
            == ["Newer", "Older"])
    }
}
