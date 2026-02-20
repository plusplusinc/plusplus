import Foundation
import SwiftData

@Model
final class ExerciseGroup {
    var workout: Workout?
    var order: Int
    var sets: Int
    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.group)
    var exercises: [WorkoutExercise] = []

    init(order: Int = 0, sets: Int = 3) {
        self.order = order
        self.sets = sets
    }

    var sortedExercises: [WorkoutExercise] {
        exercises.filter { !$0.isDeleted }.sorted { $0.order < $1.order }
    }

    var isSuperset: Bool {
        exercises.count > 1
    }

    func reindexExercises() {
        for (index, exercise) in sortedExercises.filter({ !$0.isDeleted }).enumerated() {
            exercise.order = index
        }
    }
}
