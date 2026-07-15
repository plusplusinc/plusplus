import Foundation

/// Which metrics an exercise tracks, and what its distance numbers mean.
/// The profile decides what the planning sheet and set screen expose: a
/// dumbbell curl tracks [weight, reps]; a rower tracks [distance, duration,
/// pace, resistance]; a push-up tracks [reps] and shows no dead weight row.
///
/// Pure value logic. The app stores a profile as Kit-encoded JSON on the
/// exercise (additive column; nil falls back to the seed catalog's
/// assignment for built-ins, else to the legacy ExerciseType).
public struct MetricProfile: Equatable, Codable, Sendable {
    /// Tracked metrics in canonical order (WorkoutMetric declaration
    /// order), deduped, block configuration (`.rest`/`.transition`)
    /// excluded — those shape the pause after a set, they aren't tracked
    /// quantities.
    public private(set) var metrics: [WorkoutMetric]
    /// What this exercise's distance/pace/speed numbers are denominated
    /// in. Meaningless (and ignored) unless one of those is tracked.
    public var distanceUnit: DistanceUnit
    /// Whether this is an outdoor, GPS-trackable locomotion activity (a
    /// road run/walk) — the signal that engages live pace/distance from
    /// GPS. Distinguishes an outdoor run from an erg or treadmill that
    /// also tracks distance/pace but has no location.
    ///
    /// ⚠️ Read `isOutdoor` ONLY off a DECODED profile (`Exercise`/`SetLog`
    /// resolve theirs from stored JSON, or the seed catalog). The
    /// `(metrics:distanceUnit:isOutdoor:)` initializer defaults it to
    /// false, so a profile RECONSTRUCTED from another's `.metrics` (the
    /// set screen's `secondaryMetricsList`, the watch's `targetText`)
    /// does NOT carry the flag — those sites never read it.
    public var isOutdoor: Bool

    public init(_ metrics: [WorkoutMetric], distanceUnit: DistanceUnit = .meters, isOutdoor: Bool = false) {
        self.metrics = WorkoutMetric.allCases.filter { !$0.isBlockConfiguration && metrics.contains($0) }
        self.distanceUnit = distanceUnit
        self.isOutdoor = isOutdoor
    }

    // Decoding routes through the normalizing init so stored or
    // hand-edited JSON can't smuggle in duplicate/misordered metrics, and
    // a missing unit falls back to meters like everywhere else.
    private enum CodingKeys: String, CodingKey {
        case metrics, distanceUnit, isOutdoor
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Unknown metric strings are dropped, not fatal — a newer file's
        // future metric shouldn't brick the whole profile.
        let rawMetrics = try container.decode([String].self, forKey: .metrics)
        let unit = try container.decodeIfPresent(DistanceUnit.self, forKey: .distanceUnit) ?? .meters
        // Absent in pre-outdoor blobs → false, like distanceUnit's fallback.
        let outdoor = try container.decodeIfPresent(Bool.self, forKey: .isOutdoor) ?? false
        self.init(rawMetrics.compactMap(WorkoutMetric.init(rawValue:)), distanceUnit: unit, isOutdoor: outdoor)
    }

    // MARK: - Common shapes

    /// The classic strength profile — what ExerciseType.weightReps meant.
    public static let weightReps = MetricProfile([.weight, .reps])
    /// What ExerciseType.duration meant.
    public static let durationOnly = MetricProfile([.duration])
    /// Bodyweight rep work — no dead weight row.
    public static let repsOnly = MetricProfile([.reps])

    /// The profile a legacy ExerciseType implies — pre-profile stores and
    /// old interchange files decode through this, byte-for-byte behavior
    /// preserved.
    public static func derived(from type: ExerciseType) -> MetricProfile {
        type == .duration ? .durationOnly : .weightReps
    }

    // MARK: - Semantics

    public func contains(_ metric: WorkoutMetric) -> Bool {
        metrics.contains(metric)
    }

    public var tracksReps: Bool { contains(.reps) }

    /// Whether the profile carries any load-like metric — drives the
    /// weight/assist card and per-equipment step relevance.
    public var tracksLoad: Bool { contains(.weight) || contains(.assistance) }

    /// A profile must track at least one WORK metric (reps, distance,
    /// calories, or duration) — "weight" alone doesn't say what doing a
    /// set means.
    public var isValid: Bool {
        metrics.contains(where: \.isWorkMetric)
    }

    /// The legacy type this profile maps onto, for old readers (interchange
    /// exerciseType, the watch's isDuration): rep-tracked profiles are
    /// weightReps, everything else rides duration.
    public var legacyType: ExerciseType {
        tracksReps ? .weightReps : .duration
    }

    /// The metric that DRIVES execution of a set — decides the set-screen
    /// mode (reps → log flow, duration → auto-timer, distance/calories →
    /// target card + manual log). The highest-priority work metric that has
    /// a target wins, so the same rower can run 4×500m in one routine
    /// (distance target set → distance-driven) and a 20-minute steady piece
    /// in another (duration target set → timer). Falls back to the first
    /// tracked work metric, then `.reps` for degenerate profiles.
    public func driver(targets: (WorkoutMetric) -> Double?) -> WorkoutMetric {
        let tracked = WorkoutMetric.workMetrics.filter(contains)
        return tracked.first { targets($0) != nil } ?? tracked.first ?? .reps
    }

    /// Everything tracked except the given driver — the set screen's
    /// secondary rows, in canonical order.
    public func secondaryMetrics(driver: WorkoutMetric) -> [WorkoutMetric] {
        metrics.filter { $0 != driver }
    }

    // MARK: - Storage codec (the RoutineSchedule Data-column pattern)

    public static func decode(from data: Data?) -> MetricProfile? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(MetricProfile.self, from: data)
    }

    public func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(self)
    }
}

/// Codec for the per-row metric value bags (targets, actuals, defaults
/// beyond the weight/reps/duration columns): `[WorkoutMetric: Double]`
/// stored as one additive Data column, and `[String: Double]` at the
/// interchange boundary so unknown future keys pass through untyped.
public enum MetricValues {
    public static func decode(_ data: Data?) -> [WorkoutMetric: Double] {
        guard let data,
              let raw = try? JSONDecoder().decode([String: Double].self, from: data)
        else { return [:] }
        return fromRaw(raw)
    }

    /// nil when empty, so untouched rows stay nil instead of carrying "{}"
    /// blobs. Sorted keys — stored bytes are deterministic like every
    /// other serialization in the project.
    public static func encode(_ values: [WorkoutMetric: Double]) -> Data? {
        guard !values.isEmpty, let raw = toRaw(values) else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(raw)
    }

    /// Unknown keys are dropped — a newer file's future metric can't be
    /// edited here, and silently carrying it would lie about fidelity.
    public static func fromRaw(_ raw: [String: Double]?) -> [WorkoutMetric: Double] {
        guard let raw else { return [:] }
        var values: [WorkoutMetric: Double] = [:]
        for (key, value) in raw {
            if let metric = WorkoutMetric(rawValue: key) {
                values[metric] = value
            }
        }
        return values
    }

    public static func toRaw(_ values: [WorkoutMetric: Double]) -> [String: Double]? {
        guard !values.isEmpty else { return nil }
        return Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) })
    }
}
