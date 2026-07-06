import Foundation
import Testing
import SwiftData
@testable import PlusPlus

@Suite("Workout time estimate")
struct WorkoutEstimateTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Exercise.self, Equipment.self, Workout.self, ExerciseGroup.self, WorkoutExercise.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test("Weight sets count 45 s each; timed sets use their target; rest fills between")
    func estimate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let workout = Workout(name: "W", restSeconds: 60)
        context.insert(workout)

        let bench = Exercise(name: "Bench Press", muscleGroup: .chest)
        let plank = Exercise(name: "Plank", muscleGroup: .core, exerciseType: .duration)
        context.insert(bench)
        context.insert(plank)

        let liftGroup = workout.addExerciseInNewGroup(bench, context: context) // 3 sets default
        let plankGroup = workout.addExerciseInNewGroup(plank, context: context)
        plankGroup.sets = 2
        plankGroup.sortedExercises[0].durationSeconds = 90

        // Work: 3×45 + 2×90 = 315; rest: (5-1)×60 = 240.
        _ = liftGroup
        #expect(workout.estimatedSeconds == 555)
    }

    @Test("Empty workout estimates zero")
    func emptyEstimate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let workout = Workout(name: "W")
        context.insert(workout)
        #expect(workout.estimatedSeconds == 0)
    }
}
