import Foundation
import SwiftData

@Model
final class Workout {
    var name: String
    var createdAt: Date
    var order: Int
    /// Rest between sets during execution, in seconds.
    var restSeconds: Int = 90
    /// Freeform intent for the whole workout ("keep it under an hour",
    /// "finisher optional") — shown at session start.
    var notes: String?
    @Relationship(deleteRule: .cascade, inverse: \ExerciseGroup.workout)
    var groups: [ExerciseGroup] = []

    init(name: String, order: Int = 0, restSeconds: Int = 90, notes: String? = nil) {
        self.name = name
        self.createdAt = Date()
        self.order = order
        self.restSeconds = restSeconds
        self.notes = notes
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

    /// Rough all-in seconds for the detail meta line: ~45 s of work per
    /// weight set, the actual target for timed sets, plus rest between
    /// sets (matches the v2 prototype's estimate).
    var estimatedSeconds: Int {
        var work = 0
        var totalSets = 0
        for group in sortedGroups {
            for entry in group.sortedExercises {
                let perSet = entry.exercise?.exerciseType == .duration
                    ? (entry.durationSeconds ?? 45)
                    : 45
                work += perSet * group.sets
                totalSets += group.sets
            }
        }
        return work + max(0, totalSets - 1) * restSeconds
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
        applyDefaultTargets(to: workoutExercise, for: exercise)
        workoutExercise.group = group
        context.insert(workoutExercise)

        reindexGroups()
        return group
    }

    /// Fresh entries start with the design's defaults (10 reps / 45 s)
    /// instead of blank targets.
    private func applyDefaultTargets(to entry: WorkoutExercise, for exercise: Exercise) {
        if exercise.exerciseType == .duration {
            entry.durationSeconds = 45
        } else {
            entry.reps = 10
        }
    }

    /// Adds an exercise to an existing group, making (or extending) a superset.
    func addExercise(_ exercise: Exercise, to group: ExerciseGroup, context: ModelContext) {
        let workoutExercise = WorkoutExercise(exercise: exercise, order: group.exercises.count)
        applyDefaultTargets(to: workoutExercise, for: exercise)
        workoutExercise.group = group
        context.insert(workoutExercise)
        group.reindexExercises()
    }

    /// Merges a solo group's exercise into the adjacent group (direction
    /// -1 = above, +1 = below), forming or extending a superset there.
    /// No-op when the group isn't solo or there is no neighbor (the v2
    /// design only offers the action for solo rows).
    func mergeSoloGroup(_ group: ExerciseGroup, direction: Int, context: ModelContext) {
        let sorted = sortedGroups
        guard group.sortedExercises.count == 1,
              let index = sorted.firstIndex(where: { $0 === group }),
              sorted.indices.contains(index + direction),
              let moving = group.sortedExercises.first
        else { return }

        let target = sorted[index + direction]
        if direction < 0 {
            moving.order = target.exercises.count
            moving.group = target
        } else {
            for member in target.sortedExercises {
                member.order += 1
            }
            moving.order = 0
            moving.group = target
        }
        target.reindexExercises()
        context.delete(group)
        reindexGroups()
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
