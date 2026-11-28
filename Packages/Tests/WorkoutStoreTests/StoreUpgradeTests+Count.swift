import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

extension StoreUpgradeTests {
    @Test("A V11 store opens its workout with no count and no time added, then keeps both")
    func upgradeBeforeCount() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "StoreUpgrade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "PlusPlus.store")
        let rowID = UUID()

        do {
            let schema = Schema(versionedSchema: RoutineSchemaV11.self)
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
                exerciseID: "plank",
                position: 0,
            )
            context.insert(row)
            row.routine = workout
            let workoutSession = RoutineSchemaV11.StoredWorkout(id: UUID())
            workoutSession.routineID = workout.id
            workoutSession.startedAt = Date(timeIntervalSinceReferenceDate: 2)
            context.insert(workoutSession)
            let set = RoutineSchemaV11.StoredSet(id: UUID())
            set.rowID = rowID
            set.exerciseID = "plank"
            set.seconds = 30
            set.plannedSeconds = 30
            set.clockWhenLogged = 30
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
        #expect(workoutSession.count == nil)
        #expect(workoutSession.sets.map(\.timeAdded) == [0])
        #expect(workoutSession.sets.map(\.clockWhenLogged) == [30])

        let count = SetCount(
            set: PlannedSet(row: rowID, round: 2, side: .left),
            startClock: 40,
            added: 15,
        )
        workoutSession.count = count
        workoutSession.sets[0].timeAdded = 15
        try await store.save(workoutSession)
        let relaunched = try await Store(modelContainer: current)
            .launch(weightUnit: .pounds).workoutSession
        #expect(relaunched?.count == count)
        #expect(relaunched?.sets.map(\.timeAdded) == [15])
    }
}
