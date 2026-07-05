import Foundation
import SwiftData

@Model
final class Workout {
    var name: String
    var createdAt: Date
    var order: Int
    @Relationship(deleteRule: .cascade, inverse: \ExerciseGroup.workout)
    var groups: [ExerciseGroup] = []

    init(name: String, order: Int = 0) {
        self.name = name
        self.createdAt = Date()
        self.order = order
    }

    var sortedGroups: [ExerciseGroup] {
        groups.filter { !$0.isDeleted }.sorted { $0.order < $1.order }
    }

    var equipmentNames: [String] {
        let names = sortedGroups
            .flatMap { $0.sortedExercises }
            .compactMap { $0.exercise }
            .flatMap { $0.equipment }
            .map { $0.name }
        return Array(Set(names)).sorted()
    }

    func reindexGroups() {
        for (index, group) in sortedGroups.filter({ !$0.isDeleted }).enumerated() {
            group.order = index
        }
    }

    // MARK: - Structure mutations
    // All group/exercise structure changes go through these so the order
    // invariants hold; views should not assemble groups by hand.

    /// Adds an exercise in its own new group at the end of the workout.
    @discardableResult
    func addExerciseInNewGroup(_ exercise: Exercise, context: ModelContext) -> ExerciseGroup {
        let group = ExerciseGroup(order: groups.count, sets: 3)
        group.workout = self
        context.insert(group)

        let workoutExercise = WorkoutExercise(exercise: exercise, order: 0)
        workoutExercise.group = group
        context.insert(workoutExercise)

        reindexGroups()
        return group
    }

    /// Adds an exercise to an existing group, making (or extending) a superset.
    func addExercise(_ exercise: Exercise, to group: ExerciseGroup, context: ModelContext) {
        let workoutExercise = WorkoutExercise(exercise: exercise, order: group.exercises.count)
        workoutExercise.group = group
        context.insert(workoutExercise)
        group.reindexExercises()
    }

    /// Moves a superset member out into its own group, placed immediately
    /// after the group it came from. No-op for a solo exercise.
    func splitExercise(_ workoutExercise: WorkoutExercise, context: ModelContext) {
        guard let sourceGroup = workoutExercise.group, sourceGroup.isSuperset else { return }

        let insertionOrder = sourceGroup.order + 1
        for group in sortedGroups where group.order >= insertionOrder {
            group.order += 1
        }

        let newGroup = ExerciseGroup(order: insertionOrder, sets: sourceGroup.sets)
        newGroup.workout = self
        context.insert(newGroup)

        workoutExercise.group = newGroup
        workoutExercise.order = 0

        sourceGroup.reindexExercises()
        reindexGroups()
    }
}
