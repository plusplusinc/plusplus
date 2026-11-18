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
        let names = try ModelContext(container).fetch(FetchDescriptor<StoredSet>())
            .map(\.exerciseName)
        #expect(names == ["Barbell bench press", "Barbell bench press"])
    }
}
