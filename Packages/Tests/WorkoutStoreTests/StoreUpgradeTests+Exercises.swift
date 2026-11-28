import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

extension StoreUpgradeTests {
    @Test("A store written in V7 opens with its workouts and logged one, then keeps a created one")
    func upgradeBeforeCreatedExercises() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "StoreUpgrade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "PlusPlus.store")
        let workoutID = UUID()
        let rowID = UUID()

        do {
            let schema = Schema(versionedSchema: RoutineSchemaV7.self)
            let old = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url),
            )
            let context = ModelContext(old)
            let workout = RoutineSchemaV7.StoredRoutine(id: workoutID)
            workout.name = "Upper"
            workout.editedAt = Date(timeIntervalSinceReferenceDate: 1)
            context.insert(workout)
            let row = RoutineSchemaV7.StoredRoutineExercise(
                id: rowID,
                exerciseID: "dumbbell-row",
                position: 0,
            )
            row.sets = 4
            row.rest = 75
            row.isRestAuto = false
            context.insert(row)
            row.routine = workout
            let workoutSession = RoutineSchemaV6.StoredWorkout(id: UUID())
            workoutSession.routineID = workoutID
            workoutSession.routineName = "Upper"
            workoutSession.startedAt = Date(timeIntervalSinceReferenceDate: 2)
            context.insert(workoutSession)
            try context.save()
        }

        let current = try ModelContainer(
            for: Store.schema,
            migrationPlan: StoreMigrationPlan.self,
            configurations: ModelConfiguration(schema: Store.schema, url: url),
        )
        let store = Store(modelContainer: current)
        let launch = try await store.launch(weightUnit: .pounds)
        let workout = try #require(launch.workout)
        #expect(launch.workoutSession?.workoutID == workoutID)
        #expect(workout.name == "Upper")
        #expect(workout.exercises.map(\.id) == [rowID])
        #expect(workout.exercises.first?.plan.sets == 4)
        #expect(workout.exercises.first?.plan.rest == .byHand(75))
        #expect(try await store.exercises() == .builtIn)

        let created = CreatedExercise(name: "Ring row with rotation", muscleGroups: [.back])
        try await store.save(created)
        var edited = workout
        edited.exercises.append(WorkoutExercise(
            exercise: Exercise(created: created),
            weightUnit: .pounds,
        ))
        try await store.save(edited, keepsEmpty: true)
        let reopened = Store(modelContainer: current)
        #expect(try await reopened.exercises() == ExerciseList(created: [created]))
        #expect(try await reopened.launch(weightUnit: .pounds).workout == edited)
    }

    @Test("A V8 store's exercise of one muscle group opens with that group, in its workout")
    func oneGroupExercise() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "StoreUpgrade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "PlusPlus.store")
        let exerciseID = CreatedExercise.newID()
        let workoutID = UUID()

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
            let workout = RoutineSchemaV7.StoredRoutine(id: workoutID)
            workout.editedAt = Date(timeIntervalSinceReferenceDate: 2)
            context.insert(workout)
            let row = RoutineSchemaV7.StoredRoutineExercise(
                id: UUID(),
                exerciseID: exerciseID,
                position: 0,
            )
            context.insert(row)
            row.routine = workout
            try context.save()
        }

        let current = try ModelContainer(
            for: Store.schema,
            migrationPlan: StoreMigrationPlan.self,
            configurations: ModelConfiguration(schema: Store.schema, url: url),
        )
        let store = Store(modelContainer: current)
        let list = try await store.exercises()
        let exercise = try #require(list.exercise(id: exerciseID))
        #expect(exercise.muscleGroups == [.back])
        #expect(exercise.equipment == [.rings])
        let workout = try #require(try await store.launch(weightUnit: .pounds).workout)
        #expect(workout.exercises.map(\.exercise) == [exercise])

        // Saved again with a second group, it reads back with both.
        var both = try #require(try ModelContext(current)
            .fetch(FetchDescriptor<StoredExercise>()).first?.created)
        both.muscleGroups = [.back, .shoulders]
        try await store.save(both)
        let reread = try await Store(modelContainer: current).exercises()
        #expect(reread.exercise(id: exerciseID)?.muscleGroups == [.back, .shoulders])
    }

    @Test("A V8 store's logged set opens with no name kept, then a set logged keeps its name")
    func upgradeBeforeLoggedNames() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "StoreUpgrade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "PlusPlus.store")
        let workoutID = UUID()
        let rowID = UUID()

        do {
            let schema = Schema(versionedSchema: RoutineSchemaV8.self)
            let old = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url),
            )
            let context = ModelContext(old)
            let workout = RoutineSchemaV7.StoredRoutine(id: workoutID)
            workout.name = "Upper"
            workout.editedAt = Date(timeIntervalSinceReferenceDate: 1)
            context.insert(workout)
            let row = RoutineSchemaV7.StoredRoutineExercise(
                id: rowID,
                exerciseID: "push-up",
                position: 0,
            )
            context.insert(row)
            row.routine = workout
            let workoutSession = RoutineSchemaV6.StoredWorkout(id: UUID())
            workoutSession.routineID = workoutID
            workoutSession.routineName = "Upper"
            workoutSession.startedAt = Date(timeIntervalSinceReferenceDate: 2)
            context.insert(workoutSession)
            let set = RoutineSchemaV6.StoredSet(id: UUID())
            set.rowID = rowID
            set.exerciseID = "push-up"
            set.reps = 10
            set.plannedReps = 10
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
        let launch = try await Store(modelContainer: current).launch(weightUnit: .pounds)
        var workoutSession = try #require(launch.workoutSession)
        let workout = try #require(launch.workout)
        #expect(workoutSession.sets.map(\.exerciseID) == ["push-up"])
        #expect(workoutSession.sets.map(\.exerciseName) == [nil])

        let next = try #require(workout.nextSet(after: workoutSession.sets))
        workoutSession = workoutSession.logging(next, of: workout.exercises[0], at: .now)
        try await Store(modelContainer: current).save(workoutSession)
        let reread = try await Store(modelContainer: current).launch(weightUnit: .pounds)
        #expect(reread.workoutSession?.sets.map(\.exerciseName) == [nil, "Push-up"])
    }

    @Test("A V9 store opens with nothing customized, then keeps a built-in's customization")
    func upgradeBeforeCustomizations() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "StoreUpgrade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "PlusPlus.store")
        let workoutID = UUID()
        let rowID = UUID()

        do {
            let schema = Schema(versionedSchema: RoutineSchemaV9.self)
            let old = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url),
            )
            let context = ModelContext(old)
            let workout = RoutineSchemaV7.StoredRoutine(id: workoutID)
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
            workoutSession.routineID = workoutID
            workoutSession.routineName = "Push"
            workoutSession.startedAt = Date(timeIntervalSinceReferenceDate: 2)
            context.insert(workoutSession)
            let set = RoutineSchemaV9.StoredSet(id: UUID())
            set.rowID = rowID
            set.exerciseID = "barbell-bench-press"
            set.exerciseName = "Barbell bench press"
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
        #expect(try await store.exercises() == .builtIn)
        let launch = try await store.launch(weightUnit: .pounds)
        #expect(launch.workout?.exercises.map(\.id) == [rowID])
        #expect(launch.workoutSession?.sets.map(\.exerciseName) == ["Barbell bench press"])

        let bench = try #require(Exercise.builtIn(id: "barbell-bench-press"))
        var settings = bench.settings
        settings.muscleGroups = [.chest, .arms]
        try await store.save(Customization(of: bench, to: settings))
        // Its row, in a second store on the file, reads the customization.
        let workout = try await Store(modelContainer: current).launch(weightUnit: .pounds)
            .workout
        #expect(workout?.exercises.first?.exercise.muscleGroups == [.chest, .arms])
    }
}
