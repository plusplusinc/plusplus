import Foundation
import SwiftData
import PlusPlusKit

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
    /// Encoded HeartRateTarget — the optional cardio prescription
    /// ("zone 2", "130–150 bpm"). Stored as JSON Data (nil = none) so
    /// the SwiftData migration is additive, like Routine.scheduleData.
    var heartRateTargetData: Data?

    init(exercise: Exercise, order: Int = 0) {
        self.exercise = exercise
        self.order = order
    }

    /// Typed view over `heartRateTargetData`.
    var heartRateTarget: HeartRateTarget? {
        get {
            heartRateTargetData.flatMap { try? JSONDecoder().decode(HeartRateTarget.self, from: $0) }
        }
        set {
            heartRateTargetData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }

    /// A routine edit is the freshest statement of intent for this
    /// exercise, so it becomes the default for future adds (#187).
    /// Copies the whole target state for the exercise's type — including
    /// nil — so the default always mirrors the last-edited entry.
    func bumpExerciseDefaults() {
        guard let exercise else { return }
        if exercise.exerciseType == .duration {
            exercise.defaultDurationSeconds = durationSeconds
            exercise.defaultHeartRateTargetData = heartRateTargetData
        } else {
            exercise.defaultWeight = weight
            exercise.defaultReps = reps
            exercise.defaultRepsUpper = repsUpper
        }
    }
}
