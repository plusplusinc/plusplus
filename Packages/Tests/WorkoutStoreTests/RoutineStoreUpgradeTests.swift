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
            .launchRoutine(weightUnit: .pounds))
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
            .launchRoutine(weightUnit: .pounds))
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
        #expect(try await store.launchRoutine(weightUnit: .pounds)?.name == "Newer")
        #expect(try await store.routinesByRecency(weightUnit: .pounds).routines.map(\.name)
            == ["Newer", "Older"])
    }
}
