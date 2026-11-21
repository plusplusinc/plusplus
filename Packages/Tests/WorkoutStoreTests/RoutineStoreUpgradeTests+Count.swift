import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

extension RoutineStoreUpgradeTests {
    @Test("A V11 store opens its workout with no count and no time added, then keeps both")
    func upgradeBeforeCount() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "RoutineStoreUpgrade-\(UUID().uuidString)")
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
            let routine = RoutineSchemaV7.StoredRoutine(id: UUID())
            routine.editedAt = Date(timeIntervalSinceReferenceDate: 1)
            context.insert(routine)
            let row = RoutineSchemaV7.StoredRoutineExercise(
                id: rowID,
                exerciseID: "plank",
                position: 0,
            )
            context.insert(row)
            row.routine = routine
            let workout = RoutineSchemaV11.StoredWorkout(id: UUID())
            workout.routineID = routine.id
            workout.startedAt = Date(timeIntervalSinceReferenceDate: 2)
            context.insert(workout)
            let set = RoutineSchemaV11.StoredSet(id: UUID())
            set.rowID = rowID
            set.exerciseID = "plank"
            set.seconds = 30
            set.plannedSeconds = 30
            set.clockWhenLogged = 30
            context.insert(set)
            set.workout = workout
            try context.save()
        }

        let current = try ModelContainer(
            for: RoutineStore.schema,
            migrationPlan: RoutineMigrationPlan.self,
            configurations: ModelConfiguration(schema: RoutineStore.schema, url: url),
        )
        let store = RoutineStore(modelContainer: current)
        var workout = try #require(try await store.launch(weightUnit: .pounds).workout)
        #expect(workout.count == nil)
        #expect(workout.sets.map(\.timeAdded) == [0])
        #expect(workout.sets.map(\.clockWhenLogged) == [30])

        let count = SetCount(
            set: PlannedSet(row: rowID, round: 2, side: .left),
            startClock: 40,
            added: 15,
        )
        workout.count = count
        workout.sets[0].timeAdded = 15
        try await store.save(workout)
        let relaunched = try await RoutineStore(modelContainer: current)
            .launch(weightUnit: .pounds).workout
        #expect(relaunched?.count == count)
        #expect(relaunched?.sets.map(\.timeAdded) == [15])
    }
}
