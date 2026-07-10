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
    /// Targets for metrics beyond the columns above (distance, pace,
    /// resistance, …) — one Kit-encoded [metric: value] bag. Additive;
    /// nil for every pre-profile row.
    var extraTargetsData: Data?

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

    var extraTargets: [WorkoutMetric: Double] {
        get { MetricValues.decode(extraTargetsData) }
        set { extraTargetsData = MetricValues.encode(newValue) }
    }

    /// One lookup/store for any metric's target, columns and bag alike.
    /// Reps stays Int-backed (plus its range column); callers that need
    /// the range keep using `reps`/`repsUpper` directly.
    func target(_ metric: WorkoutMetric) -> Double? {
        switch metric {
        case .weight: weight
        case .reps: reps.map(Double.init)
        case .duration: durationSeconds.map(Double.init)
        default: extraTargets[metric]
        }
    }

    func setTarget(_ metric: WorkoutMetric, to value: Double?) {
        switch metric {
        case .weight: weight = value
        case .reps: reps = value.map { Int($0.rounded()) }
        case .duration: durationSeconds = value.map { Int($0.rounded()) }
        default:
            var extras = extraTargets
            extras[metric] = value
            extraTargets = extras
        }
    }

    /// A routine edit is the freshest statement of intent for this
    /// exercise, so it becomes the default for future adds (#187).
    /// Copies the whole target state for each TRACKED metric — including
    /// nil — so the default always mirrors the last-edited entry. The
    /// heart-rate prescription rides the same rule on cardio entries.
    func bumpExerciseDefaults() {
        guard let exercise else { return }
        let profile = exercise.metricProfile
        var extras: [WorkoutMetric: Double] = [:]
        for metric in profile.metrics {
            switch metric {
            case .weight:
                exercise.defaultWeight = weight
            case .reps:
                exercise.defaultReps = reps
                exercise.defaultRepsUpper = repsUpper
            case .duration:
                exercise.defaultDurationSeconds = durationSeconds
            default:
                extras[metric] = extraTargets[metric]
            }
        }
        exercise.extraDefaults = extras
        if profile.legacyType == .duration {
            exercise.defaultHeartRateTargetData = heartRateTargetData
        }
    }
}
