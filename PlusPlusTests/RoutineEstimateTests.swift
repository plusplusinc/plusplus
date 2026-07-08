import Foundation
import Testing
import SwiftData
@testable import PlusPlus

@Suite("Routine time estimate")
struct RoutineEstimateTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Exercise.self, Equipment.self, Routine.self, ExerciseGroup.self, RoutineExercise.self])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("routineestimate-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, groupContainer: .none, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test("Weight sets count 45 s each; timed sets use their target; rest fills between")
    func estimate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = Routine(name: "W", restSeconds: 60)
        context.insert(routine)

        let bench = Exercise(name: "Bench Press", muscleGroup: .chest)
        let plank = Exercise(name: "Plank", muscleGroup: .core, exerciseType: .duration)
        context.insert(bench)
        context.insert(plank)

        let liftGroup = routine.addExerciseInNewGroup(bench, context: context) // 3 sets default
        let plankGroup = routine.addExerciseInNewGroup(plank, context: context)
        plankGroup.sets = 2
        plankGroup.sortedExercises[0].durationSeconds = 90

        // Work: 3×45 + 2×90 = 315; rest: (5-1)×60 = 240.
        _ = liftGroup
        #expect(routine.estimatedSeconds == 555)
    }

    @Test("Empty routine estimates zero")
    func emptyEstimate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = Routine(name: "W")
        context.insert(routine)
        #expect(routine.estimatedSeconds == 0)
    }
}
