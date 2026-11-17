import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

extension RoutineStoreUpgradeTests {
    @Test("A store written in V7 opens with its routines and workout, then keeps a created one")
    func upgradeBeforeCreatedExercises() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "RoutineStoreUpgrade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "PlusPlus.store")
        let routineID = UUID()
        let rowID = UUID()

        do {
            let schema = Schema(versionedSchema: RoutineSchemaV7.self)
            let old = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url),
            )
            let context = ModelContext(old)
            let routine = RoutineSchemaV7.StoredRoutine(id: routineID)
            routine.name = "Upper"
            routine.editedAt = Date(timeIntervalSinceReferenceDate: 1)
            context.insert(routine)
            let row = RoutineSchemaV7.StoredRoutineExercise(
                id: rowID,
                exerciseID: "dumbbell-row",
                position: 0,
            )
            row.sets = 4
            row.rest = 75
            row.isRestAuto = false
            context.insert(row)
            row.routine = routine
            let workout = RoutineSchemaV6.StoredWorkout(id: UUID())
            workout.routineID = routineID
            workout.routineName = "Upper"
            workout.startedAt = Date(timeIntervalSinceReferenceDate: 2)
            context.insert(workout)
            try context.save()
        }

        let current = try ModelContainer(
            for: RoutineStore.schema,
            migrationPlan: RoutineMigrationPlan.self,
            configurations: ModelConfiguration(schema: RoutineStore.schema, url: url),
        )
        let store = RoutineStore(modelContainer: current)
        let launch = try await store.launch(weightUnit: .pounds)
        let routine = try #require(launch.routine)
        #expect(launch.workout?.routineID == routineID)
        #expect(routine.name == "Upper")
        #expect(routine.exercises.map(\.id) == [rowID])
        #expect(routine.exercises.first?.plan.sets == 4)
        #expect(routine.exercises.first?.plan.rest == .byHand(75))
        #expect(try await store.exercises() == .builtIn)

        let created = CreatedExercise(name: "Ring row with rotation", muscleGroup: .back)
        try await store.save(created)
        var edited = routine
        edited.exercises.append(RoutineExercise(
            exercise: Exercise(created: created),
            weightUnit: .pounds,
        ))
        try await store.save(edited, keepsEmpty: true)
        let reopened = RoutineStore(modelContainer: current)
        #expect(try await reopened.exercises() == ExerciseList(created: [created]))
        #expect(try await reopened.launch(weightUnit: .pounds).routine == edited)
    }
}
