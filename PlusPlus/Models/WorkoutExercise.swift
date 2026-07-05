import Foundation
import SwiftData

@Model
final class WorkoutExercise {
    var group: ExerciseGroup?
    var exercise: Exercise?
    var order: Int
    var weight: Double?
    var reps: Int?
    /// Upper bound of a target rep range (e.g. 20 in "15–20"). nil means
    /// `reps` is a single target. Only meaningful when `reps` is set.
    var repsUpper: Int?
    var durationSeconds: Int?

    init(exercise: Exercise, order: Int = 0) {
        self.exercise = exercise
        self.order = order
    }
}
