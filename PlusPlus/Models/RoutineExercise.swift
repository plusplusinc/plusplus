import Foundation
import SwiftData

@Model
final class RoutineExercise {
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

    /// A routine edit is the freshest statement of intent for this
    /// exercise, so it becomes the default for future adds (#187).
    /// Copies the whole target state for the exercise's type — including
    /// nil — so the default always mirrors the last-edited entry.
    func bumpExerciseDefaults() {
        guard let exercise else { return }
        if exercise.exerciseType == .duration {
            exercise.defaultDurationSeconds = durationSeconds
        } else {
            exercise.defaultWeight = weight
            exercise.defaultReps = reps
            exercise.defaultRepsUpper = repsUpper
        }
    }
}
