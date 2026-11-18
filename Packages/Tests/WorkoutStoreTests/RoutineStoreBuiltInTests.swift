import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

/// A built-in customized and cleared after routines use it. A relaunch is a second store over
/// the same container: it sees only what was saved.
@Suite("Routine store, customizing a built-in")
struct RoutineStoreBuiltInTests {
    private let container: ModelContainer

    init() throws {
        container = try WorkoutStoreContainer.make(mode: .inMemory, schema: RoutineStore.schema)
    }

    private func relaunch() -> RoutineStore {
        RoutineStore(modelContainer: container)
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
    private static func row() throws -> RoutineExercise {
        var row = try RoutineExercise(exercise: #require(bench), weightUnit: .pounds)
        row.plan.sets = 4
        row.plan.target = .reps(8)
        row.plan.weight = Weight(135, .pounds)
        return row
    }

    private func reread(_ id: Routine.ID) async throws -> RoutineExercise {
        try #require(try await relaunch().routine(id, weightUnit: .pounds)?.exercises.first)
    }

    @Test("A built-in's new muscle group reaches every routine's row, its numbers and rest kept")
    func groupsKeepNumbersAndRest() async throws {
        let store = relaunch()
        let routines = try [
            Routine(name: "A", exercises: [Self.row()]),
            Routine(name: "B", exercises: [Self.row()]),
        ]
        for routine in routines {
            try await store.save(routine)
        }
        for groups: Set<MuscleGroup> in [[.chest, .arms], [.legs], []] {
            try await relaunch().save(Self.customized { $0.muscleGroups = groups })
            for routine in routines {
                let row = try await reread(routine.id)
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
        let cleared = try await reread(routines[0].id)
        #expect(cleared.exercise == Self.bench)
        #expect(try cleared.plan == Self.row().plan)
    }

    @Test("A built-in's rename keeps the name a set was logged under, a nil one filled first")
    func renameKeepsLoggedNames() async throws {
        let store = relaunch()
        let routine = try Routine(name: "Push", exercises: [Self.row()])
        try await store.save(routine)
        var workout = Workout(
            routineID: routine.id,
            routineName: "Push",
            startedAt: Date(timeIntervalSinceReferenceDate: 10),
        )
        for second in [20.0, 30] {
            let next = try #require(routine.nextSet(after: workout.sets))
            workout = workout.logging(
                next,
                of: routine.exercises[0],
                at: Date(timeIntervalSinceReferenceDate: second),
            )
        }
        try await store.save(workout)
        // One logged before V9 stored a name.
        let context = ModelContext(container)
        let first = try #require(try context.fetch(FetchDescriptor<StoredSet>(
            sortBy: [SortDescriptor(\.position)],
        )).first)
        first.exerciseName = nil
        try context.save()

        try await relaunch().save(Self.customized { $0.name = "Bench press" })
        #expect(try await reread(routine.id).exercise.name == "Bench press")
        #expect(try loggedNames() == ["Barbell bench press", "Barbell bench press"])

        // Logged after the rename, it keeps that name once the rename is cleared.
        let renamed = try #require(try await relaunch().routine(routine.id, weightUnit: .pounds))
        let next = try #require(renamed.nextSet(after: workout.sets))
        workout = workout.logging(
            next,
            of: renamed.exercises[0],
            at: Date(timeIntervalSinceReferenceDate: 40),
        )
        try await relaunch().save(workout)
        try await relaunch().clearCustomizations("barbell-bench-press")
        #expect(try await reread(routine.id).exercise.name == "Barbell bench press")
        #expect(try loggedNames() == ["Barbell bench press", "Barbell bench press", "Bench press"])
    }

    /// Every logged set's name, in the order logged.
    private func loggedNames() throws -> [String?] {
        try ModelContext(container).fetch(FetchDescriptor<StoredSet>(
            sortBy: [SortDescriptor(\.position)],
        )).map(\.exerciseName)
    }

    @Test("Clearing every customization brings back what shipped, every routine's numbers kept")
    func clearRoundTrip() async throws {
        let routine = try Routine(name: "Push", exercises: [Self.row()])
        try await relaunch().save(routine)
        let before = try await reread(routine.id)
        try await relaunch().save(Self.customized {
            $0.name = "Bench press"
            $0.muscleGroups = [.arms]
            $0.equipment = [.dumbbells]
            $0.measure = .time
            $0.isPerSide = true
        })
        let changed = try await reread(routine.id)
        #expect(changed.exercise.name == "Bench press")
        #expect(changed.exercise.load == .single)
        #expect(changed.plan.target == .time(seconds: 30))

        try await relaunch().clearCustomizations("barbell-bench-press")
        #expect(try await relaunch().exercises() == .builtIn)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<StoredCustomization>()) == 0)
        let cleared = try await reread(routine.id)
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
