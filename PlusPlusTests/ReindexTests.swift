import Foundation
import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

@Suite("Reindex")
struct ReindexTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Exercise.self, Equipment.self, Routine.self, ExerciseGroup.self, RoutineExercise.self])
        let config = ModelConfiguration("reindex-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Routine.reindexGroups

    @Test func reindexGroupsAssignsSequentialOrders() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let routine = Routine(name: "Test")
        context.insert(routine)

        for i in 0..<3 {
            let group = ExerciseGroup(order: i * 10) // arbitrary initial orders
            group.routine = routine
            context.insert(group)
        }

        routine.reindexGroups()
        let orders = routine.sortedGroups.map(\.order)
        #expect(orders == [0, 1, 2])
    }

    @Test func reindexGroupsAfterDeleteFillsGap() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let routine = Routine(name: "Test")
        context.insert(routine)

        var groups: [ExerciseGroup] = []
        for i in 0..<3 {
            let group = ExerciseGroup(order: i)
            group.routine = routine
            context.insert(group)
            groups.append(group)
        }

        // Delete middle group
        context.delete(groups[1])
        routine.reindexGroups()

        let orders = routine.sortedGroups.map(\.order)
        #expect(orders == [0, 1])
    }

    @Test func reindexGroupsAfterMoveUpdatesCorrectly() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let routine = Routine(name: "Test")
        context.insert(routine)

        let groupA = ExerciseGroup(order: 0)
        groupA.routine = routine
        context.insert(groupA)

        let groupB = ExerciseGroup(order: 1)
        groupB.routine = routine
        context.insert(groupB)

        let groupC = ExerciseGroup(order: 2)
        groupC.routine = routine
        context.insert(groupC)

        // Simulate moving last to first
        groupC.order = -1
        routine.reindexGroups()

        let sorted = routine.sortedGroups
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
            let we = RoutineExercise(exercise: exercise, order: i * 5)
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

        var routineExercises: [RoutineExercise] = []
        for i in 0..<3 {
            let we = RoutineExercise(exercise: exercise, order: i)
            we.group = group
            context.insert(we)
            routineExercises.append(we)
        }

        context.delete(routineExercises[1])
        group.reindexExercises()

        let orders = group.sortedExercises.map(\.order)
        #expect(orders == [0, 1])
    }
}
