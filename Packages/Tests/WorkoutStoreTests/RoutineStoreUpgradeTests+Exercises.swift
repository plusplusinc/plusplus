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

        let created = CreatedExercise(name: "Ring row with rotation", muscleGroups: [.back])
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

    @Test("A V8 store's exercise of one muscle group opens with that group, in its routine")
    func oneGroupExercise() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "RoutineStoreUpgrade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "PlusPlus.store")
        let exerciseID = CreatedExercise.newID()
        let routineID = UUID()

        // As the build with one group per exercise wrote it: the group's raw value alone.
        do {
            let schema = Schema(versionedSchema: RoutineSchemaV8.self)
            let old = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url),
            )
            let context = ModelContext(old)
            let stored = RoutineSchemaV8.StoredExercise(id: exerciseID)
            stored.name = "Ring row with rotation"
            stored.muscleGroup = "back"
            stored.equipment = "rings"
            stored.createdAt = Date(timeIntervalSinceReferenceDate: 1)
            context.insert(stored)
            let routine = RoutineSchemaV7.StoredRoutine(id: routineID)
            routine.editedAt = Date(timeIntervalSinceReferenceDate: 2)
            context.insert(routine)
            let row = RoutineSchemaV7.StoredRoutineExercise(
                id: UUID(),
                exerciseID: exerciseID,
                position: 0,
            )
            context.insert(row)
            row.routine = routine
            try context.save()
        }

        let current = try ModelContainer(
            for: RoutineStore.schema,
            migrationPlan: RoutineMigrationPlan.self,
            configurations: ModelConfiguration(schema: RoutineStore.schema, url: url),
        )
        let store = RoutineStore(modelContainer: current)
        let list = try await store.exercises()
        let exercise = try #require(list.exercise(id: exerciseID))
        #expect(exercise.muscleGroups == [.back])
        #expect(exercise.equipment == [.rings])
        let routine = try #require(try await store.launch(weightUnit: .pounds).routine)
        #expect(routine.exercises.map(\.exercise) == [exercise])

        // Saved again with a second group, it reads back with both.
        var both = try #require(try ModelContext(current)
            .fetch(FetchDescriptor<StoredExercise>()).first?.created)
        both.muscleGroups = [.back, .shoulders]
        try await store.save(both)
        let reread = try await RoutineStore(modelContainer: current).exercises()
        #expect(reread.exercise(id: exerciseID)?.muscleGroups == [.back, .shoulders])
    }

    @Test("A V8 store's logged set opens with no name kept, then a set logged keeps its name")
    func upgradeBeforeLoggedNames() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "RoutineStoreUpgrade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "PlusPlus.store")
        let routineID = UUID()
        let rowID = UUID()

        do {
            let schema = Schema(versionedSchema: RoutineSchemaV8.self)
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
                exerciseID: "push-up",
                position: 0,
            )
            context.insert(row)
            row.routine = routine
            let workout = RoutineSchemaV6.StoredWorkout(id: UUID())
            workout.routineID = routineID
            workout.routineName = "Upper"
            workout.startedAt = Date(timeIntervalSinceReferenceDate: 2)
            context.insert(workout)
            let set = RoutineSchemaV6.StoredSet(id: UUID())
            set.rowID = rowID
            set.exerciseID = "push-up"
            set.reps = 10
            set.plannedReps = 10
            set.loggedAt = Date(timeIntervalSinceReferenceDate: 3)
            context.insert(set)
            set.workout = workout
            try context.save()
        }

        let current = try ModelContainer(
            for: RoutineStore.schema,
            migrationPlan: RoutineMigrationPlan.self,
            configurations: ModelConfiguration(schema: RoutineStore.schema, url: url),
        )
        let launch = try await RoutineStore(modelContainer: current).launch(weightUnit: .pounds)
        var workout = try #require(launch.workout)
        let routine = try #require(launch.routine)
        #expect(workout.sets.map(\.exerciseID) == ["push-up"])
        #expect(workout.sets.map(\.exerciseName) == [nil])

        let next = try #require(routine.nextSet(after: workout.sets))
        workout = workout.logging(next, of: routine.exercises[0], at: .now)
        try await RoutineStore(modelContainer: current).save(workout)
        let reread = try await RoutineStore(modelContainer: current).launch(weightUnit: .pounds)
        #expect(reread.workout?.sets.map(\.exerciseName) == [nil, "Push-up"])
    }
}
