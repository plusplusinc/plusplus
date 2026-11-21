import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

@Suite("Workout store upgrade")
struct StoreUpgradeTests {
    @Test("A store written before plans opens, each row with its exercise's defaults")
    func upgradeOnDisk() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "StoreUpgrade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "PlusPlus.store")
        let workoutID = UUID()
        let rowIDs = [UUID(), UUID()]

        do {
            let schema = Schema([
                RoutineSchemaV1.StoredRoutine.self,
                RoutineSchemaV1.StoredRoutineExercise.self,
            ])
            let old = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url),
            )
            let context = ModelContext(old)
            let workout = RoutineSchemaV1.StoredRoutine(id: workoutID)
            workout.name = "Upper"
            workout.editedAt = .now
            context.insert(workout)
            for (position, (id, exercise)) in zip(rowIDs, ["dumbbell-row", "pigeon-stretch"])
                .enumerated()
            {
                let row = RoutineSchemaV1.StoredRoutineExercise(
                    id: id,
                    exerciseID: exercise,
                    position: position,
                )
                context.insert(row)
                row.routine = workout
            }
            try context.save()
        }

        let current = try ModelContainer(
            for: Store.schema,
            migrationPlan: StoreMigrationPlan.self,
            configurations: ModelConfiguration(schema: Store.schema, url: url),
        )
        let workout = try #require(try await Store(modelContainer: current)
            .launch(weightUnit: .pounds).workout)
        let expected = try Exercise.builtIn(named: ["Dumbbell row", "Pigeon stretch"])
        #expect(workout.id == workoutID)
        #expect(workout.name == "Upper")
        #expect(workout.exercises.map(\.id) == rowIDs)
        #expect(workout.exercises.map(\.plan) == expected.map { $0.defaultPlan(in: .pounds) })
    }

    @Test("A store written before supersets opens with every row plain, plans kept")
    func upgradeBeforeSupersets() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "StoreUpgrade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "PlusPlus.store")
        let rowIDs = [UUID(), UUID()]

        do {
            let schema = Schema([
                RoutineSchemaV2.StoredRoutine.self,
                RoutineSchemaV2.StoredRoutineExercise.self,
            ])
            let old = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url),
            )
            let context = ModelContext(old)
            let workout = RoutineSchemaV2.StoredRoutine(id: UUID())
            workout.editedAt = .now
            context.insert(workout)
            for (position, (id, exercise)) in zip(rowIDs, ["push-up", "pull-up"]).enumerated() {
                let row = RoutineSchemaV2.StoredRoutineExercise(
                    id: id,
                    exerciseID: exercise,
                    position: position,
                )
                row.sets = 5
                row.reps = 8
                context.insert(row)
                row.routine = workout
            }
            try context.save()
        }

        let current = try ModelContainer(
            for: Store.schema,
            migrationPlan: StoreMigrationPlan.self,
            configurations: ModelConfiguration(schema: Store.schema, url: url),
        )
        let workout = try #require(try await Store(modelContainer: current)
            .launch(weightUnit: .pounds).workout)
        #expect(workout.exercises.map(\.id) == rowIDs)
        #expect(workout.exercises.allSatisfy { $0.supersetID == nil })
        #expect(workout.exercises.map(\.plan.sets) == [5, 5])
        #expect(workout.exercises.map(\.plan.target) == [.reps(8), .reps(8)])
    }

    @Test("A store written before workouts were opened opens in edited order")
    func upgradeBeforeOpening() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "StoreUpgrade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "PlusPlus.store")

        do {
            let schema = Schema([
                RoutineSchemaV3.StoredRoutine.self,
                RoutineSchemaV3.StoredRoutineExercise.self,
            ])
            let old = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url),
            )
            let context = ModelContext(old)
            for (name, seconds) in [("Older", 1.0), ("Newer", 2.0)] {
                let workout = RoutineSchemaV3.StoredRoutine(id: UUID())
                workout.name = name
                workout.editedAt = Date(timeIntervalSinceReferenceDate: seconds)
                context.insert(workout)
            }
            try context.save()
        }

        let current = try ModelContainer(
            for: Store.schema,
            migrationPlan: StoreMigrationPlan.self,
            configurations: ModelConfiguration(schema: Store.schema, url: url),
        )
        let store = Store(modelContainer: current)
        #expect(try await store.launch(weightUnit: .pounds).workout?.name == "Newer")
        #expect(try await store.workoutsByRecency(weightUnit: .pounds).map(\.name)
            == ["Newer", "Older"])
    }

    @Test(
        "A store written before logged workouts opens with every workout, then keeps a logged one",
    )
    func upgradeBeforeLoggedWorkouts() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "StoreUpgrade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "PlusPlus.store")
        try Self.writeBeforeLoggedWorkouts(to: url)

        func open() throws -> Store {
            try Store(modelContainer: ModelContainer(
                for: Store.schema,
                migrationPlan: StoreMigrationPlan.self,
                configurations: ModelConfiguration(schema: Store.schema, url: url),
            ))
        }

        let store = try open()
        let workouts = try await store.workoutsByRecency(weightUnit: .pounds)
        #expect(workouts.map(\.name) == ["Older", "Newer"])
        for workout in workouts {
            #expect(workout.exercises.map(\.exercise.id) == ["push-up", "pull-up"])
            #expect(workout.exercises.map(\.plan.sets) == [4, 4])
            #expect(workout.exercises.map(\.plan.target) == [.reps(6), .reps(6)])
            #expect(workout.exercises.allSatisfy { $0.supersetID != nil })
        }
        let loggedWorkout = LoggedWorkout(
            workoutID: workouts[0].id,
            workoutName: workouts[0].name,
            startedAt: Date(timeIntervalSinceReferenceDate: 10),
        )
        try await store.save(loggedWorkout)

        let launch = try await open().launch(weightUnit: .pounds)
        #expect(launch.loggedWorkout == loggedWorkout)
        #expect(launch.workout?.name == "Older")
    }

    @Test("A store written before logged sets opens with its workout in progress, no sets")
    func upgradeBeforeSets() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "StoreUpgrade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "PlusPlus.store")
        try Self.writeBeforeLoggedWorkouts(to: url)
        let loggedWorkoutID = UUID()
        do {
            let schema = Schema(versionedSchema: RoutineSchemaV5.self)
            let old = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url),
            )
            let context = ModelContext(old)
            let workout = try #require(try context
                .fetch(FetchDescriptor<StoredRoutine>())
                .first { $0.name == "Older" })
            let loggedWorkout = RoutineSchemaV5.StoredWorkout(id: loggedWorkoutID)
            loggedWorkout.routineID = workout.id
            loggedWorkout.routineName = "Older"
            loggedWorkout.startedAt = Date(timeIntervalSinceReferenceDate: 10)
            context.insert(loggedWorkout)
            try context.save()
        }

        let current = try ModelContainer(
            for: Store.schema,
            migrationPlan: StoreMigrationPlan.self,
            configurations: ModelConfiguration(schema: Store.schema, url: url),
        )
        let launch = try await Store(modelContainer: current).launch(weightUnit: .pounds)
        #expect(launch.loggedWorkout?.id == loggedWorkoutID)
        #expect(launch.loggedWorkout?.sets == [])
        #expect(launch.workout?.name == "Older")
    }

    /// Today's workouts as #91 stored them: two, each with a superset of two rows with plans,
    /// one opened after the other's edit.
    static func writeBeforeLoggedWorkouts(to url: URL) throws {
        let schema = Schema([
            RoutineSchemaV4.StoredRoutine.self,
            RoutineSchemaV4.StoredRoutineExercise.self,
        ])
        let old = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, url: url),
        )
        let context = ModelContext(old)
        for (name, edited, opened) in [("Older", 1.0, 3.0), ("Newer", 2.0, 0.0)] {
            let workout = RoutineSchemaV4.StoredRoutine(id: UUID())
            workout.name = name
            workout.editedAt = Date(timeIntervalSinceReferenceDate: edited)
            workout.openedAt = Date(timeIntervalSinceReferenceDate: opened)
            context.insert(workout)
            let supersetID = UUID()
            for (position, exercise) in ["push-up", "pull-up"].enumerated() {
                let row = RoutineSchemaV4.StoredRoutineExercise(
                    id: UUID(),
                    exerciseID: exercise,
                    position: position,
                )
                row.sets = 4
                row.reps = 6
                row.supersetID = supersetID
                context.insert(row)
                row.routine = workout
            }
        }
        try context.save()
    }
}
