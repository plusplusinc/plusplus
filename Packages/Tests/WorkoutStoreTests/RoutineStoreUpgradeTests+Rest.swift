import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

extension RoutineStoreUpgradeTests {
    @Test("A store written before rest opens with every rest automatic, a superset's too")
    func upgradeBeforeRest() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "RoutineStoreUpgrade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "PlusPlus.store")
        try Self.writeBeforeLoggedWorkouts(to: url)
        do {
            // Touch the store in V6's shape, so the upgrade starts from it.
            let schema = Schema(versionedSchema: RoutineSchemaV6.self)
            let old = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url),
            )
            let context = ModelContext(old)
            let loggedWorkout = RoutineSchemaV6.StoredWorkout(id: UUID())
            loggedWorkout.routineName = "Older"
            context.insert(loggedWorkout)
            try context.save()
        }

        let current = try ModelContainer(
            for: RoutineStore.schema,
            migrationPlan: RoutineMigrationPlan.self,
            configurations: ModelConfiguration(schema: RoutineStore.schema, url: url),
        )
        let routines = try await RoutineStore(modelContainer: current)
            .routinesByRecency(weightUnit: .pounds)
        #expect(routines.count == 2)
        for routine in routines {
            #expect(routine.exercises.allSatisfy { $0.plan.rest == .neverSet })
            #expect(routine.exercises.map(\.rest) == [60, 90])
            #expect(routine.exercises.allSatisfy { $0.roundRest == .neverSet })
            #expect(routine.restAfterRound(of: routine.exercises[0].id) == 30)
        }
    }

    @Test("A V10 store opens its workout's sets with no rest kept, then keeps a rest's clock")
    func upgradeBeforeRestClock() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "RoutineStoreUpgrade-\(UUID().uuidString)")
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
            let routine = RoutineSchemaV7.StoredRoutine(id: UUID())
            routine.editedAt = Date(timeIntervalSinceReferenceDate: 1)
            context.insert(routine)
            let row = RoutineSchemaV7.StoredRoutineExercise(
                id: rowID,
                exerciseID: "barbell-bench-press",
                position: 0,
            )
            context.insert(row)
            row.routine = routine
            let loggedWorkout = RoutineSchemaV9.StoredWorkout(id: UUID())
            loggedWorkout.routineID = routine.id
            loggedWorkout.startedAt = Date(timeIntervalSinceReferenceDate: 2)
            context.insert(loggedWorkout)
            let set = RoutineSchemaV9.StoredSet(id: UUID())
            set.rowID = rowID
            set.exerciseID = "barbell-bench-press"
            set.reps = 5
            set.plannedReps = 5
            set.loggedAt = Date(timeIntervalSinceReferenceDate: 3)
            context.insert(set)
            set.workout = loggedWorkout
            try context.save()
        }

        let current = try ModelContainer(
            for: RoutineStore.schema,
            migrationPlan: RoutineMigrationPlan.self,
            configurations: ModelConfiguration(schema: RoutineStore.schema, url: url),
        )
        let store = RoutineStore(modelContainer: current)
        var loggedWorkout = try #require(try await store.launch(weightUnit: .pounds).loggedWorkout)
        #expect(loggedWorkout.sets.map(\.clockWhenLogged) == [nil])
        #expect(loggedWorkout.sets.map(\.restAdjustment) == [0])

        loggedWorkout.sets[0].clockWhenLogged = 1
        loggedWorkout.sets[0].restAdjustment = 15
        try await store.save(loggedWorkout)
        let relaunched = try await RoutineStore(modelContainer: current)
            .launch(weightUnit: .pounds).loggedWorkout
        #expect(relaunched?.sets.map(\.clockWhenLogged) == [1])
        #expect(relaunched?.sets.map(\.restAdjustment) == [15])
    }
}
