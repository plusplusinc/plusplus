import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

extension StoreUpgradeTests {
    @Test("A V12 store opens with no rest skipped, a skip's cut kept, then keeps a skip")
    func upgradeBeforeSkip() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "StoreUpgrade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "PlusPlus.store")
        let rowID = UUID()

        do {
            let schema = Schema(versionedSchema: RoutineSchemaV12.self)
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
                exerciseID: "push-up",
                position: 0,
            )
            context.insert(row)
            row.routine = workout
            let loggedWorkout = RoutineSchemaV12.StoredWorkout(id: UUID())
            loggedWorkout.routineID = workout.id
            loggedWorkout.startedAt = Date(timeIntervalSinceReferenceDate: 2)
            context.insert(loggedWorkout)
            // A rest skipped under V12: its cut stored as the adjustment.
            let set = RoutineSchemaV12.StoredSet(id: UUID())
            set.rowID = rowID
            set.exerciseID = "push-up"
            set.reps = 10
            set.plannedReps = 10
            set.clockWhenLogged = 30
            set.restAdjustment = -40
            context.insert(set)
            set.workout = loggedWorkout
            try context.save()
        }

        let current = try ModelContainer(
            for: Store.schema,
            migrationPlan: StoreMigrationPlan.self,
            configurations: ModelConfiguration(schema: Store.schema, url: url),
        )
        let store = Store(modelContainer: current)
        var loggedWorkout = try #require(try await store.launch(weightUnit: .pounds).loggedWorkout)
        #expect(loggedWorkout.sets.map(\.restSkippedAt) == [nil])
        #expect(loggedWorkout.sets.map(\.restAdjustment) == [-40])
        #expect(loggedWorkout.sets.map(\.clockWhenLogged) == [30])

        loggedWorkout.sets[0].restSkippedAt = 42.5
        try await store.save(loggedWorkout)
        let relaunched = try await Store(modelContainer: current)
            .launch(weightUnit: .pounds).loggedWorkout
        #expect(relaunched?.sets.map(\.restSkippedAt) == [42.5])
        #expect(relaunched?.sets.map(\.restAdjustment) == [-40])
    }
}
