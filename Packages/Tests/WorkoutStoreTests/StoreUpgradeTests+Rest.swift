import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

extension StoreUpgradeTests {
    @Test("A store written before rest opens with every rest automatic, a superset's too")
    func upgradeBeforeRest() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "StoreUpgrade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "PlusPlus.store")
        try Self.writeBeforeWorkoutSessions(to: url)
        do {
            // Touch the store in V6's shape, so the upgrade starts from it.
            let schema = Schema(versionedSchema: RoutineSchemaV6.self)
            let old = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url),
            )
            let context = ModelContext(old)
            let workoutSession = RoutineSchemaV6.StoredWorkout(id: UUID())
            workoutSession.routineName = "Older"
            context.insert(workoutSession)
            try context.save()
        }

        let current = try ModelContainer(
            for: Store.schema,
            migrationPlan: StoreMigrationPlan.self,
            configurations: ModelConfiguration(schema: Store.schema, url: url),
        )
        let workouts = try await Store(modelContainer: current)
            .workoutsByRecency(weightUnit: .pounds)
        #expect(workouts.count == 2)
        for workout in workouts {
            #expect(workout.exercises.allSatisfy { $0.plan.rest == .neverSet })
            #expect(workout.exercises.map(\.rest) == [60, 90])
            #expect(workout.exercises.allSatisfy { $0.roundRest == .neverSet })
            #expect(workout.restAfterRound(of: workout.exercises[0].id) == 30)
        }
    }

    @Test("A V10 store opens its workout's sets with no rest kept, then keeps a rest's clock")
    func upgradeBeforeRestClock() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "StoreUpgrade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "PlusPlus.store")
        let rowID = UUID()

        do {
            let schema = Schema(versionedSchema: RoutineSchemaV10.self)
            let old = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url),
            )
            let context = ModelContext(old)
            let workout = RoutineSchemaV7.StoredRoutine(id: UUID())
            workout.editedAt = Date(timeIntervalSinceReferenceDate: 1)
            context.insert(workout)
            let row = RoutineSchemaV7.StoredRoutineExercise(
                id: rowID,
                exerciseID: "barbell-bench-press",
                position: 0,
            )
            context.insert(row)
            row.routine = workout
            let workoutSession = RoutineSchemaV9.StoredWorkout(id: UUID())
            workoutSession.routineID = workout.id
            workoutSession.startedAt = Date(timeIntervalSinceReferenceDate: 2)
            context.insert(workoutSession)
            let set = RoutineSchemaV9.StoredSet(id: UUID())
            set.rowID = rowID
            set.exerciseID = "barbell-bench-press"
            set.reps = 5
            set.plannedReps = 5
            set.loggedAt = Date(timeIntervalSinceReferenceDate: 3)
            context.insert(set)
            set.workout = workoutSession
            try context.save()
        }

        let current = try ModelContainer(
            for: Store.schema,
            migrationPlan: StoreMigrationPlan.self,
            configurations: ModelConfiguration(schema: Store.schema, url: url),
        )
        let store = Store(modelContainer: current)
        var workoutSession = try #require(try await store.launch(weightUnit: .pounds)
            .workoutSession)
        #expect(workoutSession.sets.map(\.clockWhenLogged) == [nil])
        #expect(workoutSession.sets.map(\.restAdjustment) == [0])

        workoutSession.sets[0].clockWhenLogged = 1
        workoutSession.sets[0].restAdjustment = 15
        try await store.save(workoutSession)
        let relaunched = try await Store(modelContainer: current)
            .launch(weightUnit: .pounds).workoutSession
        #expect(relaunched?.sets.map(\.clockWhenLogged) == [1])
        #expect(relaunched?.sets.map(\.restAdjustment) == [15])
    }
}
