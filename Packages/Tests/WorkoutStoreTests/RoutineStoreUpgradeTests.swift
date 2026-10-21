import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

@Suite("Routine store upgrade")
struct RoutineStoreUpgradeTests {
    @Test("A store written before plans opens, each row with its exercise's defaults")
    func upgradeOnDisk() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "RoutineStoreUpgrade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "PlusPlus.store")
        let routineID = UUID()
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
            let routine = RoutineSchemaV1.StoredRoutine(id: routineID)
            routine.name = "Upper"
            routine.editedAt = .now
            context.insert(routine)
            for (position, (id, exercise)) in zip(rowIDs, ["dumbbell-row", "pigeon-stretch"])
                .enumerated()
            {
                let row = RoutineSchemaV1.StoredRoutineExercise(
                    id: id,
                    exerciseID: exercise,
                    position: position,
                )
                context.insert(row)
                row.routine = routine
            }
            try context.save()
        }

        let current = try ModelContainer(
            for: RoutineStore.schema,
            migrationPlan: RoutineMigrationPlan.self,
            configurations: ModelConfiguration(schema: RoutineStore.schema, url: url),
        )
        let routine = try #require(try await RoutineStore(modelContainer: current)
            .launch(weightUnit: .pounds).routine)
        let expected = try Exercise.builtIn(named: ["Dumbbell row", "Pigeon stretch"])
        #expect(routine.id == routineID)
        #expect(routine.name == "Upper")
        #expect(routine.exercises.map(\.id) == rowIDs)
        #expect(routine.exercises.map(\.plan) == expected.map { $0.defaultPlan(in: .pounds) })
    }

    @Test("A store written before supersets opens with every row plain, plans kept")
    func upgradeBeforeSupersets() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "RoutineStoreUpgrade-\(UUID().uuidString)")
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
            let routine = RoutineSchemaV2.StoredRoutine(id: UUID())
            routine.editedAt = .now
            context.insert(routine)
            for (position, (id, exercise)) in zip(rowIDs, ["push-up", "pull-up"]).enumerated() {
                let row = RoutineSchemaV2.StoredRoutineExercise(
                    id: id,
                    exerciseID: exercise,
                    position: position,
                )
                row.sets = 5
                row.reps = 8
                context.insert(row)
                row.routine = routine
            }
            try context.save()
        }

        let current = try ModelContainer(
            for: RoutineStore.schema,
            migrationPlan: RoutineMigrationPlan.self,
            configurations: ModelConfiguration(schema: RoutineStore.schema, url: url),
        )
        let routine = try #require(try await RoutineStore(modelContainer: current)
            .launch(weightUnit: .pounds).routine)
        #expect(routine.exercises.map(\.id) == rowIDs)
        #expect(routine.exercises.allSatisfy { $0.supersetID == nil })
        #expect(routine.exercises.map(\.plan.sets) == [5, 5])
        #expect(routine.exercises.map(\.plan.target) == [.reps(8), .reps(8)])
    }

    @Test("A store written before routines were opened opens in edited order")
    func upgradeBeforeOpening() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "RoutineStoreUpgrade-\(UUID().uuidString)")
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
                let routine = RoutineSchemaV3.StoredRoutine(id: UUID())
                routine.name = name
                routine.editedAt = Date(timeIntervalSinceReferenceDate: seconds)
                context.insert(routine)
            }
            try context.save()
        }

        let current = try ModelContainer(
            for: RoutineStore.schema,
            migrationPlan: RoutineMigrationPlan.self,
            configurations: ModelConfiguration(schema: RoutineStore.schema, url: url),
        )
        let store = RoutineStore(modelContainer: current)
        #expect(try await store.launch(weightUnit: .pounds).routine?.name == "Newer")
        #expect(try await store.routinesByRecency(weightUnit: .pounds).routines.map(\.name)
            == ["Newer", "Older"])
    }

    @Test("A store written before workouts opens with every routine, then keeps a workout")
    func upgradeBeforeWorkouts() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "RoutineStoreUpgrade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "PlusPlus.store")
        let supersetID = UUID()

        do {
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
                let routine = RoutineSchemaV4.StoredRoutine(id: UUID())
                routine.name = name
                routine.editedAt = Date(timeIntervalSinceReferenceDate: edited)
                routine.openedAt = Date(timeIntervalSinceReferenceDate: opened)
                context.insert(routine)
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
                    row.routine = routine
                }
            }
            try context.save()
        }

        func open() throws -> RoutineStore {
            try RoutineStore(modelContainer: ModelContainer(
                for: RoutineStore.schema,
                migrationPlan: RoutineMigrationPlan.self,
                configurations: ModelConfiguration(schema: RoutineStore.schema, url: url),
            ))
        }

        let store = try open()
        let routines = try await store.routinesByRecency(weightUnit: .pounds).routines
        #expect(routines.map(\.name) == ["Older", "Newer"])
        for routine in routines {
            #expect(routine.exercises.map(\.exercise.id) == ["push-up", "pull-up"])
            #expect(routine.exercises.map(\.plan.sets) == [4, 4])
            #expect(routine.exercises.map(\.plan.target) == [.reps(6), .reps(6)])
            #expect(routine.exercises.allSatisfy { $0.supersetID != nil })
        }
        let workout = Workout(
            routineID: routines[0].id,
            routineName: routines[0].name,
            startedAt: Date(timeIntervalSinceReferenceDate: 10),
        )
        try await store.save(workout)

        let launch = try await open().launch(weightUnit: .pounds)
        #expect(launch.workout == workout)
        #expect(launch.routine?.name == "Older")
    }
}
