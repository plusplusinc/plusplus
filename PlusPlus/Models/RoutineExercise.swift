import Foundation
import SwiftData
import PlusPlusKit

@Model
final class RoutineExercise {
    var group: ExerciseGroup?
    var exercise: Exercise?
    /// Stable identity for presentation (the per-exercise detail sheet keys
    /// on it) — see `Routine.uuid`. Set in init (no property default, which
    /// a migration would stamp as one shared constant); backfilled if nil or
    /// duplicated. Device-local, not in the interchange.
    var uuid: UUID?
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
        self.uuid = UUID()
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

    /// The entry's WHOLE target set as one value — the six fields that
    /// together are "what this entry prescribes" (#508, b19).
    ///
    /// ⚠️ It exists so the field list lives in exactly ONE place. Every
    /// site that fills an entry's targets used to spell the list out by
    /// hand, and `duplicateExercise` had already drifted: it copied
    /// weight/reps/repsUpper/duration/heart rate and silently dropped
    /// `extraTargetsData`, so duplicating a configured cardio entry lost
    /// its distance, pace and resistance — the exact bag, and only the
    /// bag. A hand-written list drifts the moment a seventh field is
    /// added; assigning this property cannot.
    ///
    /// The type is `Exercise.AddTimeTargets` because that struct already
    /// IS this list (it is what `addTimeTargets` prefills FROM). Its name
    /// now undersells it — it is the entry-target shape generally, not
    /// only the add-time one — but renaming it is a wider change than
    /// this round, and a second identical struct would be the drift over
    /// again.
    var targets: Exercise.AddTimeTargets {
        get {
            Exercise.AddTimeTargets(
                weight: weight,
                reps: reps,
                repsUpper: repsUpper,
                durationSeconds: durationSeconds,
                heartRateTargetData: heartRateTargetData,
                extraTargets: extraTargets
            )
        }
        set {
            weight = newValue.weight
            reps = newValue.reps
            repsUpper = newValue.repsUpper
            durationSeconds = newValue.durationSeconds
            heartRateTargetData = newValue.heartRateTargetData
            extraTargets = newValue.extraTargets
        }
    }

    /// One lookup/store for any metric's target, columns and bag alike.
    /// Reps stays Int-backed (plus its range column); callers that need
    /// the range keep using `reps`/`repsUpper` directly.
    func target(_ metric: WorkoutMetric) -> Double? {
        switch metric {
        case .weight: weight
        case .reps: reps.map(Double.init)
        case .duration: durationSeconds.map(Double.init)
        // Pre-profile assisted prescriptions lived in the weight
        // column; the seed-table flip to [assistance, reps] must not
        // strand them (mirrors SetLog's actual/target bridge).
        case .assistance: extraTargets[.assistance] ?? weight
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
