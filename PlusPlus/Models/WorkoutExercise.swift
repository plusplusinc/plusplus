import Foundation
import SwiftData

@Model
final class WorkoutExercise {
    var group: ExerciseGroup?
    var exercise: Exercise?
    var order: Int
    var weight: Double?
    var reps: Int?
    var durationSeconds: Int?

    init(exercise: Exercise, order: Int = 0) {
        self.exercise = exercise
        self.order = order
    }
}
