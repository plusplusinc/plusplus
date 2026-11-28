import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

/// A built-in customized and cleared after workouts use it. A relaunch is a second store over
/// the same container: it sees only what was saved.
@Suite("Workout store, customizing a built-in")
struct StoreBuiltInTests {
    private let container: ModelContainer

    init() throws {
        container = try WorkoutStoreContainer.make(mode: .inMemory, schema: Store.schema)
    }

    private func relaunch() -> Store {
        Store(modelContainer: container)
    }

    private static let bench = Exercise.builtIn.first { $0.id == "barbell-bench-press" }

    /// Bench press changed by `change`.
    private static func customized(
        _ change: (inout ExerciseSettings) -> Void,
    ) throws -> Customization {
        let bench = try #require(bench)
        var settings = bench.settings
        change(&settings)
        return Customization(of: bench, to: settings)
    }

    /// A row of bench press at 4 × 8, 135 lb, its rest automatic.
    private static func row() throws -> WorkoutExercise {
        var row = try WorkoutExercise(exercise: #require(bench), weightUnit: .pounds)
        row.plan.sets = 4
        row.plan.target = .reps(8)
        row.plan.weight = Weight(135, .pounds)
        return row
    }

    private func reread(_ id: Workout.ID) async throws -> WorkoutExercise {
        try #require(try await relaunch().workout(id, weightUnit: .pounds)?.exercises.first)
    }

    @Test("A built-in's new muscle group reaches every workout's row, its numbers and rest kept")
    func groupsKeepNumbersAndRest() async throws {
        let store = relaunch()
        let workouts = try [
            Workout(name: "A", exercises: [Self.row()]),
            Workout(name: "B", exercises: [Self.row()]),
        ]
        for workout in workouts {
            try await store.save(workout)
        }
        for groups: Set<MuscleGroup> in [[.chest, .arms], [.legs], []] {
            try await relaunch().save(Self.customized { $0.muscleGroups = groups })
            for workout in workouts {
                let row = try await reread(workout.id)
                #expect(row.exercise.muscleGroups == groups)
                #expect(row.plan.sets == 4)
                #expect(row.plan.target == .reps(8))
                #expect(row.plan.weight == Weight(135, .pounds))
                // Upper-body compound at 8 reps, whatever its groups.
                #expect(row.rest == 90)
            }
        }
        try await relaunch().clearCustomizations("barbell-bench-press")
        #expect(try await relaunch().exercises() == .builtIn)
        let cleared = try await reread(workouts[0].id)
        #expect(cleared.exercise == Self.bench)
        #expect(try cleared.plan == Self.row().plan)
    }

    @Test("A built-in's rename keeps the name a set was logged under, a nil one filled first")
    func renameKeepsLoggedNames() async throws {
        let store = relaunch()
        let workout = try Workout(name: "Push", exercises: [Self.row()])
        try await store.save(workout)
        var loggedWorkout = WorkoutSession(
            workoutID: workout.id,
            workoutName: "Push",
            startedAt: Date(timeIntervalSinceReferenceDate: 10),
        )
        for second in [20.0, 30] {
            let next = try #require(workout.nextSet(after: loggedWorkout.sets))
            loggedWorkout = loggedWorkout.logging(
                next,
                of: workout.exercises[0],
                at: Date(timeIntervalSinceReferenceDate: second),
            )
        }
        try await store.save(loggedWorkout)
        // One logged before V9 stored a name.
        let context = ModelContext(container)
        let first = try #require(try context.fetch(FetchDescriptor<StoredLoggedSet>(
            sortBy: [SortDescriptor(\.position)],
        )).first)
        first.exerciseName = nil
        try context.save()

        try await relaunch().save(Self.customized { $0.name = "Bench press" })
        #expect(try await reread(workout.id).exercise.name == "Bench press")
        #expect(try loggedNames() == ["Barbell bench press", "Barbell bench press"])

        // Logged after the rename, it keeps that name once the rename is cleared.
        let renamed = try #require(try await relaunch().workout(workout.id, weightUnit: .pounds))
        let next = try #require(renamed.nextSet(after: loggedWorkout.sets))
        loggedWorkout = loggedWorkout.logging(
            next,
            of: renamed.exercises[0],
            at: Date(timeIntervalSinceReferenceDate: 40),
        )
        try await relaunch().save(loggedWorkout)
        try await relaunch().clearCustomizations("barbell-bench-press")
        #expect(try await reread(workout.id).exercise.name == "Barbell bench press")
        #expect(try loggedNames() == ["Barbell bench press", "Barbell bench press", "Bench press"])
    }

    /// Every logged set's name, in the order logged.
    private func loggedNames() throws -> [String?] {
        try ModelContext(container).fetch(FetchDescriptor<StoredLoggedSet>(
            sortBy: [SortDescriptor(\.position)],
        )).map(\.exerciseName)
    }

    @Test("Clearing every customization brings back what shipped, every workout's numbers kept")
    func clearRoundTrip() async throws {
        let workout = try Workout(name: "Push", exercises: [Self.row()])
        try await relaunch().save(workout)
        let before = try await reread(workout.id)
        try await relaunch().save(Self.customized {
            $0.name = "Bench press"
            $0.muscleGroups = [.arms]
            $0.equipment = [.dumbbells]
            $0.measure = .time
            $0.isPerSide = true
        })
        let changed = try await reread(workout.id)
        #expect(changed.exercise.name == "Bench press")
        #expect(changed.exercise.load == .single)
        #expect(changed.plan.target == .time(seconds: 30))

        try await relaunch().clearCustomizations("barbell-bench-press")
        #expect(try await relaunch().exercises() == .builtIn)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<StoredCustomization>()) == 0)
        let cleared = try await reread(workout.id)
        #expect(cleared.exercise == Self.bench)
        #expect(cleared.plan == before.plan)
        #expect(cleared.rest == before.rest)
    }

    @Test("A customization from a newer version degrades to the original, setting by setting")
    func newerCustomizationDegrades() async throws {
        let context = ModelContext(container)
        let stored = StoredCustomization(exerciseID: "barbell-bench-press")
        stored.changed = "muscle-groups,equipment,measure,tempo"
        stored.name = "Ignored, unchanged"
        stored.muscleGroups = "wings"
        stored.equipment = "barbell,antigravity-boots"
        // Another built-in's, whose equipment this build can't read at all.
        let older = StoredCustomization(exerciseID: "dumbbell-row")
        older.changed = "equipment"
        older.equipment = "antigravity-boots"
        context.insert(older)
        stored.measure = "laps"
        context.insert(stored)
        try context.save()

        let bench = try #require(Self.bench)
        let read = try #require(try await relaunch().exercises().exercise(id: bench.id))
        #expect(read.name == bench.name)
        #expect(read.muscleGroups == bench.muscleGroups)
        #expect(read.equipment == [.barbell])
        #expect(read.defaultPlan(in: .pounds).target == bench.defaultPlan(in: .pounds).target)
        let row = try await relaunch().exercises().exercise(id: "dumbbell-row")
        #expect(row == Exercise.builtIn(id: "dumbbell-row"))
    }

    @Test("Of two customizations of one built-in, as sync could leave, the later edited counts")
    func laterCustomizationWins() async throws {
        let context = ModelContext(container)
        for (name, second) in [("Later", 20.0), ("Earlier", 10)] {
            let stored = StoredCustomization(exerciseID: "barbell-bench-press")
            stored.changed = "name"
            stored.name = name
            stored.muscleGroups = "chest"
            stored.equipment = "barbell,bench"
            stored.editedAt = Date(timeIntervalSinceReferenceDate: second)
            context.insert(stored)
        }
        try context.save()
        let read = try await relaunch().exercises().exercise(id: "barbell-bench-press")
        #expect(read?.name == "Later")

        // Saved again, it is the one left.
        try await relaunch().save(Self.customized { $0.name = "Bench press" })
        let left = try ModelContext(container).fetch(FetchDescriptor<StoredCustomization>())
        #expect(left.map(\.name) == ["Bench press"])
    }
}
