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
        try Self.writeBeforeWorkouts(to: url)
        do {
            // Touch the store in V6's shape, so the upgrade starts from it.
            let schema = Schema(versionedSchema: RoutineSchemaV6.self)
            let old = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url),
            )
            let context = ModelContext(old)
            let workout = RoutineSchemaV6.StoredWorkout(id: UUID())
            workout.routineName = "Older"
            context.insert(workout)
            try context.save()
        }

        let current = try ModelContainer(
            for: RoutineStore.schema,
            migrationPlan: RoutineMigrationPlan.self,
            configurations: ModelConfiguration(schema: RoutineStore.schema, url: url),
        )
        let routines = try await RoutineStore(modelContainer: current)
            .routinesByRecency(weightUnit: .pounds).routines
        #expect(routines.count == 2)
        for routine in routines {
            #expect(routine.exercises.allSatisfy { $0.plan.rest == .neverSet })
            #expect(routine.exercises.map(\.rest) == [60, 90])
            #expect(routine.exercises.allSatisfy { $0.roundRest == .neverSet })
            #expect(routine.restAfterRound(of: routine.exercises[0].id) == 30)
        }
    }
}
