import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

@Suite("Reindex")
struct ReindexTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Exercise.self, Equipment.self, Workout.self, ExerciseGroup.self, WorkoutExercise.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Workout.reindexGroups

    @Test func reindexGroupsAssignsSequentialOrders() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let workout = Workout(name: "Test")
        context.insert(workout)

        for i in 0..<3 {
            let group = ExerciseGroup(order: i * 10) // arbitrary initial orders
            group.workout = workout
            context.insert(group)
        }

        workout.reindexGroups()
        let orders = workout.sortedGroups.map(\.order)
        #expect(orders == [0, 1, 2])
    }

    @Test func reindexGroupsAfterDeleteFillsGap() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let workout = Workout(name: "Test")
        context.insert(workout)

        var groups: [ExerciseGroup] = []
        for i in 0..<3 {
            let group = ExerciseGroup(order: i)
            group.workout = workout
            context.insert(group)
            groups.append(group)
        }

        // Delete middle group
        context.delete(groups[1])
        workout.reindexGroups()

        let orders = workout.sortedGroups.map(\.order)
        #expect(orders == [0, 1])
    }

    @Test func reindexGroupsAfterMoveUpdatesCorrectly() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let workout = Workout(name: "Test")
        context.insert(workout)

        let groupA = ExerciseGroup(order: 0)
        groupA.workout = workout
        context.insert(groupA)

        let groupB = ExerciseGroup(order: 1)
        groupB.workout = workout
        context.insert(groupB)

        let groupC = ExerciseGroup(order: 2)
        groupC.workout = workout
        context.insert(groupC)

        // Simulate moving last to first
        groupC.order = -1
        workout.reindexGroups()

        let sorted = workout.sortedGroups
        #expect(sorted[0] === groupC)
        #expect(sorted[0].order == 0)
        #expect(sorted[1].order == 1)
        #expect(sorted[2].order == 2)
    }

    // MARK: - ExerciseGroup.reindexExercises

    @Test func reindexExercisesAssignsSequentialOrders() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let group = ExerciseGroup(order: 0)
        context.insert(group)

        let exercise = Exercise(name: "Test", muscleGroup: .chest)
        context.insert(exercise)

        for i in 0..<3 {
            let we = WorkoutExercise(exercise: exercise, order: i * 5)
            we.group = group
            context.insert(we)
        }

        group.reindexExercises()
        let orders = group.sortedExercises.map(\.order)
        #expect(orders == [0, 1, 2])
    }

    @Test func reindexExercisesAfterDeleteFillsGap() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let group = ExerciseGroup(order: 0)
        context.insert(group)

        let exercise = Exercise(name: "Test", muscleGroup: .chest)
        context.insert(exercise)

        var workoutExercises: [WorkoutExercise] = []
        for i in 0..<3 {
            let we = WorkoutExercise(exercise: exercise, order: i)
            we.group = group
            context.insert(we)
            workoutExercises.append(we)
        }

        context.delete(workoutExercises[1])
        group.reindexExercises()

        let orders = group.sortedExercises.map(\.order)
        #expect(orders == [0, 1])
    }
}
