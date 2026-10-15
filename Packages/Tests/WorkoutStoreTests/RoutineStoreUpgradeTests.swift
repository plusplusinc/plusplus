import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

/// The stored shape as #68 shipped it, before rows held plans: the same entity names and only
/// the attributes it had.
private enum RoutineSchemaV1 {
    @Model
    final class StoredRoutine {
        var id = UUID()
        var name = ""
        var editedAt = Date.distantPast
        @Relationship(deleteRule: .cascade, inverse: \StoredRoutineExercise.routine)
        var exercises: [StoredRoutineExercise]? = []

        init(id: UUID) {
            self.id = id
        }
    }

    @Model
    final class StoredRoutineExercise {
        var id = UUID()
        var exerciseID = ""
        var position = 0
        var routine: StoredRoutine?

        init(id: UUID, exerciseID: String, position: Int) {
            self.id = id
            self.exerciseID = exerciseID
            self.position = position
        }
    }
}

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
}
