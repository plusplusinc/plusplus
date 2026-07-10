import Foundation
import SwiftData
import PlusPlusKit

@Model
final class Exercise {
    var name: String
    var muscleGroup: MuscleGroup
    @Relationship(inverse: \Equipment.exercises) var equipment: [Equipment] = []
    var exerciseType: ExerciseType
    var isBuiltIn: Bool
    /// Personal-library membership (v2 Library, #63). Built-ins default
    /// to true so existing stores show everything until the user prunes;
    /// removing a built-in from the library sets this false (the catalog
    /// keeps it). Customs are always in the library.
    var inLibrary: Bool = true
    var notes: String?
    var videoURL: String?
    /// Default targets (#187): what a fresh routine entry starts from.
    /// nil falls back to the metric's global default (10 reps / 45 s).
    /// Routine edits bump these — the latest prescription anywhere IS
    /// the new default — and the editor exposes them directly.
    var defaultWeight: Double?
    var defaultReps: Int?
    var defaultRepsUpper: Int?
    var defaultDurationSeconds: Int?
    /// Encoded HeartRateTarget default for cardio exercises — rides the
    /// same #187 bump rule as the other defaults.
    var defaultHeartRateTargetData: Data?
    /// Tracked-metric profile (flexible metrics), Kit-encoded JSON —
    /// additive, so no store migration. nil resolves through
    /// `metricProfile`: built-ins fall back to the seed catalog's
    /// assignment (existing stores get rich cardio profiles with zero
    /// writes), customs to the legacy exerciseType's profile.
    var metricsData: Data?
    /// Default targets for metrics beyond the three columns above —
    /// one Kit-encoded [metric: value] bag (see MetricValues).
    var extraDefaultsData: Data?

    /// Deliberately excludes the heart-rate default: this only feeds
    /// the interchange export filter, and HR targets stay out of the
    /// format until something consumes them (the scheduleData rule).
    var hasDefaultTargets: Bool {
        defaultWeight != nil || defaultReps != nil
            || defaultRepsUpper != nil || defaultDurationSeconds != nil
            || extraDefaultsData != nil
    }

    /// The resolved profile — what the planning sheet and set screen
    /// expose for this exercise. Setting it keeps the legacy
    /// `exerciseType` consistent for old readers (interchange, watch).
    var metricProfile: MetricProfile {
        get {
            if let stored = MetricProfile.decode(from: metricsData) { return stored }
            if isBuiltIn, let seeded = SeedData.builtInProfile(named: name) { return seeded }
            return .derived(from: exerciseType)
        }
        set {
            metricsData = newValue.encoded()
            exerciseType = newValue.legacyType
        }
    }

    /// Extra-metric defaults, decoded. Setter drops entries for metrics
    /// the profile doesn't track — stale values must not resurface if a
    /// metric is re-added later with different intent.
    var extraDefaults: [WorkoutMetric: Double] {
        get { MetricValues.decode(extraDefaultsData) }
        set { extraDefaultsData = MetricValues.encode(newValue) }
    }

    /// One lookup for any metric's default target, columns and bag alike.
    func defaultTarget(_ metric: WorkoutMetric) -> Double? {
        switch metric {
        case .weight: defaultWeight
        case .reps: defaultReps.map(Double.init)
        case .duration: defaultDurationSeconds.map(Double.init)
        default: extraDefaults[metric]
        }
    }

    /// The per-tap weight increment this exercise's gear implies: the
    /// smallest override among its LOADABLE equipment (microplates win
    /// over a pin stack when both are involved), nil when none is set.
    /// Non-loadable gear is skipped, not migrated (#236): pre-build-32
    /// stores can carry a step on a Bench from when every screen
    /// offered one — the card is gated now, so honoring that value
    /// would wedge stepping with no UI left to reveal or clear it.
    /// isDeleted guard mirrors ExerciseFilterState (bug hunt B1).
    var weightStepOverride: Double? {
        equipment
            .filter { !$0.isDeleted && SeedData.isLoadable($0) }
            .compactMap(\.weightStep).min()
    }

    init(
        name: String,
        muscleGroup: MuscleGroup,
        equipment: [Equipment] = [],
        exerciseType: ExerciseType = .weightReps,
        isBuiltIn: Bool = false,
        notes: String? = nil,
        videoURL: String? = nil
    ) {
        self.name = name
        self.muscleGroup = muscleGroup
        self.equipment = equipment
        self.exerciseType = exerciseType
        self.isBuiltIn = isBuiltIn
        self.notes = notes
        self.videoURL = videoURL
    }
}
