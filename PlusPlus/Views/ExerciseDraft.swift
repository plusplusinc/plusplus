import Foundation
import Observation
import PlusPlusKit

/// Editable state for creating or editing a custom exercise. Pure logic —
/// validation and normalization live here, SwiftUI-free, so they're unit
/// testable without a ModelContainer (same pattern as ExerciseFilterState).
@Observable
final class ExerciseDraft {
    var name = ""
    var muscleGroup: MuscleGroup = .chest
    /// Which metrics this exercise tracks (flexible metrics) — the
    /// editor's TRACKED VALUES chips. Normalized through MetricProfile
    /// on read, so order and duplicates never matter here.
    var trackedMetrics: [WorkoutMetric] = MetricProfile.weightReps.metrics
    var distanceUnit: DistanceUnit = .meters
    /// Whether the exercise happens outdoors under GPS (#378). Carried
    /// faithfully through the draft — dropping it was a live bug: the
    /// rebuilt profile defaulted `isOutdoor: false`, so ANY edit of
    /// Running/Walking stored an explicit indoor profile and silently
    /// killed live pace + route capture (swift-reviewer catch, fixed with
    /// the run-record work; the visible toggle ships with the record UI).
    var isOutdoor = false
    /// Latched once the user touches the metric chips: an explicit
    /// choice must never be clobbered by the equipment-based prefill.
    var metricsTouched = false
    var selectedEquipment: Set<Equipment> = []
    var notes = ""
    var videoURL = ""
    /// Default targets (#187). Optional — nil rows show "—" and fall back
    /// to the metric's global default when the exercise joins a routine.
    var defaultWeight: Double?
    var defaultReps: Int?
    var defaultRepsUpper: Int?
    var defaultDurationSeconds: Int?
    /// The heart-rate default rides the draft opaquely (no editor row
    /// yet — the planning sheet is its editing surface) so Clear and
    /// the retrack can actually drop it. Left untracked it became a
    /// ghost: "cleared" defaults kept resurrecting a stale prescription
    /// on every future add (swift-reviewer catch).
    var defaultHeartRateTargetData: Data?
    var extraDefaults: [WorkoutMetric: Double] = [:]

    init() {}

    init(from exercise: Exercise) {
        name = exercise.name
        muscleGroup = exercise.muscleGroup
        let profile = exercise.metricProfile
        trackedMetrics = profile.metrics
        distanceUnit = profile.distanceUnit
        isOutdoor = profile.isOutdoor
        // Editing an existing exercise: its profile is a fact, not a
        // suggestion — equipment changes must not rewrite it.
        metricsTouched = true
        selectedEquipment = Set(exercise.equipment)
        notes = exercise.notes ?? ""
        videoURL = exercise.videoURL ?? ""
        defaultWeight = exercise.defaultWeight
        defaultReps = exercise.defaultReps
        defaultRepsUpper = exercise.defaultRepsUpper
        defaultDurationSeconds = exercise.defaultDurationSeconds
        defaultHeartRateTargetData = exercise.defaultHeartRateTargetData
        extraDefaults = exercise.extraDefaults
    }

    // MARK: - Tracked metrics

    /// Outdoor only means something with a distance or pace metric to
    /// feed — the validator enforces the same pairing on export.
    var canBeOutdoor: Bool {
        trackedMetrics.contains(.distance) || trackedMetrics.contains(.pace)
    }

    var metricProfile: MetricProfile {
        // Dropping the last distance/pace metric drops the flag (the #187
        // stale-defaults rule generalized): a bare isOutdoor would fail
        // interchange validation and could make a repo restore throw.
        MetricProfile(trackedMetrics, distanceUnit: distanceUnit, isOutdoor: isOutdoor && canBeOutdoor)
    }

    /// The legacy type the profile maps onto (kept for old readers).
    var exerciseType: ExerciseType {
        metricProfile.legacyType
    }

    func isTracked(_ metric: WorkoutMetric) -> Bool {
        trackedMetrics.contains(metric)
    }

    /// Chip toggle. Latches `metricsTouched`.
    func toggleMetric(_ metric: WorkoutMetric) {
        metricsTouched = true
        if let index = trackedMetrics.firstIndex(of: metric) {
            trackedMetrics.remove(at: index)
        } else {
            trackedMetrics.append(metric)
        }
        trackedMetrics = MetricProfile(trackedMetrics, distanceUnit: distanceUnit).metrics
    }

    /// Whether the distance-unit choice means anything right now.
    var usesDistanceUnit: Bool {
        trackedMetrics.contains { [.distance, .pace, .speed].contains($0) }
    }

    /// Equipment-based prefill (a new exercise on a rower starts with
    /// the rower's profile). No-op once the user has spoken.
    func adoptSuggestedProfile(_ profile: MetricProfile) {
        guard !metricsTouched else { return }
        trackedMetrics = profile.metrics
        distanceUnit = profile.distanceUnit
        isOutdoor = profile.isOutdoor
    }

    /// The editor's Outdoor toggle (#378). Latches `metricsTouched`: an
    /// explicit flip is the user speaking about the profile, and the
    /// equipment-prefill re-adoption (`onChange(of: selectedEquipment)`)
    /// must never silently revert it — the toggle is off-screen when gear
    /// changes, so a clobber would be invisible (swift-reviewer catch).
    func setOutdoor(_ on: Bool) {
        isOutdoor = on
        metricsTouched = true
    }

    /// Adopt a canonical definition wholesale (revert-to-default) —
    /// an explicit act, so it counts as touched.
    func setProfile(_ profile: MetricProfile) {
        trackedMetrics = profile.metrics
        distanceUnit = profile.distanceUnit
        isOutdoor = profile.isOutdoor
        metricsTouched = true
    }

    // MARK: - Defaults

    var hasDefaultTargets: Bool {
        defaultWeight != nil || defaultReps != nil
            || defaultRepsUpper != nil || defaultDurationSeconds != nil
            || defaultHeartRateTargetData != nil
            || !extraDefaults.isEmpty
    }

    func clearDefaultTargets() {
        defaultWeight = nil
        defaultReps = nil
        defaultRepsUpper = nil
        defaultDurationSeconds = nil
        defaultHeartRateTargetData = nil
        extraDefaults = [:]
    }

    func defaultTarget(_ metric: WorkoutMetric) -> Double? {
        switch metric {
        case .weight: defaultWeight
        case .reps: defaultReps.map(Double.init)
        case .duration: defaultDurationSeconds.map(Double.init)
        default: extraDefaults[metric]
        }
    }

    func setDefaultTarget(_ metric: WorkoutMetric, to value: Double?) {
        switch metric {
        case .weight: defaultWeight = value
        case .reps: defaultReps = value.map { Int($0.rounded()) }
        case .duration: defaultDurationSeconds = value.map { Int($0.rounded()) }
        default: extraDefaults[metric] = value
        }
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum VideoURLResult: Equatable {
        case none
        case valid(String)
        case invalid
    }

    /// Empty input is fine (no video). Scheme-less input like "youtu.be/x"
    /// is upgraded to https. Anything that still doesn't parse to an
    /// http(s) URL with a host is invalid.
    var normalizedVideoURL: VideoURLResult {
        let trimmed = videoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }

        let candidate: String
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            candidate = trimmed
        } else if trimmed.contains("://") {
            return .invalid
        } else {
            candidate = "https://" + trimmed
        }

        guard let url = URL(string: candidate),
              let host = url.host, host.contains(".") else {
            return .invalid
        }
        return .valid(candidate)
    }

    /// Case-insensitive duplicate check. Pass the name being edited (if any)
    /// so an unchanged name doesn't count as its own duplicate.
    func isDuplicate(among existingNames: [String], excluding editedName: String? = nil) -> Bool {
        let target = trimmedName.lowercased()
        return existingNames.contains { candidate in
            let lowered = candidate.lowercased()
            return lowered == target && lowered != editedName?.lowercased()
        }
    }

    /// True when editing an existing exercise and the name has really
    /// changed (case-only changes keep the same slug and history match, so
    /// they don't count). A rename makes a NEW exercise identity: history
    /// stays with the old name and sync treats the old file as separate —
    /// the decided v1 semantics (issue #32).
    func isRename(of originalName: String?) -> Bool {
        guard let originalName, !trimmedName.isEmpty else { return false }
        return trimmedName.lowercased() != originalName.lowercased()
    }

    func canSave(existingNames: [String], editedName: String? = nil) -> Bool {
        !trimmedName.isEmpty
            && normalizedVideoURL != .invalid
            && !isDuplicate(among: existingNames, excluding: editedName)
            && metricProfile.isValid
    }

    /// Writes the draft onto a model object (new or existing).
    func apply(to exercise: Exercise) {
        exercise.name = trimmedName
        exercise.muscleGroup = muscleGroup
        exercise.equipment = selectedEquipment.sorted { $0.name < $1.name }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        exercise.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        if case .valid(let url) = normalizedVideoURL {
            exercise.videoURL = url
        } else {
            exercise.videoURL = nil
        }
        // A profile matching what the exercise would derive anyway
        // (catalog table for built-ins, legacy type for customs) stays
        // UNSTORED, so catalog improvements keep flowing to untouched
        // exercises and exports stay lean.
        let profile = metricProfile
        let fallback = exercise.isBuiltIn
            ? (SeedData.builtInProfile(named: exercise.name) ?? .derived(from: profile.legacyType))
            : .derived(from: profile.legacyType)
        exercise.metricsData = profile == fallback ? nil : profile.encoded()
        exercise.exerciseType = profile.legacyType
        // Defaults only make sense for tracked metrics — dropping a
        // metric drops its stale default (#187's type-switch rule,
        // generalized). The heart-rate default is cardio guidance — it
        // rides the duration family, like its planning-sheet surface.
        exercise.defaultWeight = profile.contains(.weight) ? defaultWeight : nil
        exercise.defaultReps = profile.tracksReps ? defaultReps : nil
        exercise.defaultRepsUpper = profile.tracksReps ? defaultRepsUpper : nil
        exercise.defaultDurationSeconds = profile.contains(.duration) ? defaultDurationSeconds : nil
        exercise.defaultHeartRateTargetData = profile.legacyType == .duration ? defaultHeartRateTargetData : nil
        exercise.extraDefaults = extraDefaults.filter { profile.contains($0.key) }
    }
}
