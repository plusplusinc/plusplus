import Foundation
import Testing
import SwiftData
@testable import PlusPlus

@Suite("Routine time estimate")
struct RoutineEstimateTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Exercise.self, Equipment.self, EquipmentLibrary.self, Routine.self, ExerciseGroup.self, RoutineExercise.self])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("routineestimate-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test("Weight sets count 45 s each; timed sets use their target; rest fills rounds, transitions fill boundaries")
    func estimate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = Routine(name: "W", restSeconds: 60, transitionSeconds: 15)
        context.insert(routine)

        let bench = Exercise(name: "Probe Press", muscleGroup: .chest)
        let plank = Exercise(name: "Probe Hold", muscleGroup: .core, exerciseType: .duration)
        context.insert(bench)
        context.insert(plank)

        let liftGroup = routine.addExerciseInNewGroup(bench, context: context) // 3 sets default
        let plankGroup = routine.addExerciseInNewGroup(plank, context: context)
        plankGroup.sets = 2
        plankGroup.sortedExercises[0].durationSeconds = 90

        // Work: 3×45 + 2×90 = 315; rest before new rounds: (3-1)×60 +
        // (2-1)×60 = 180; the block boundary is a transition: 15 (#369).
        _ = liftGroup
        #expect(routine.estimatedSeconds == 510)
    }

    @Test("Superset partners hand off on transitions, not rests (#369)")
    func supersetEstimate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = Routine(name: "S", restSeconds: 60, transitionSeconds: 15)
        context.insert(routine)

        let curl = Exercise(name: "Probe Curl", muscleGroup: .biceps)
        let press = Exercise(name: "Probe Press", muscleGroup: .chest)
        context.insert(curl)
        context.insert(press)

        let pair = routine.addExerciseInNewGroup(curl, context: context)
        pair.sets = 2
        routine.addExercise(press, to: pair, context: context)

        // Work: 4×45 = 180; within-round handoffs: 1×15×2 rounds = 30;
        // between rounds: (2-1)×60 = 60. No trailing pause.
        #expect(routine.estimatedSeconds == 270)
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
