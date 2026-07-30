import Foundation

public enum MuscleGroup: String, Codable, CaseIterable, Identifiable, Sendable {
    case chest, back, shoulders, biceps, triceps
    case quads, hamstrings, glutes, calves, core
    case fullBody

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .fullBody: "Full Body"
        default: rawValue.capitalized
        }
    }

    public static let grouped: [(region: String, groups: [MuscleGroup])] = [
        ("Upper Body", [.chest, .back, .shoulders, .biceps, .triceps]),
        ("Lower Body", [.quads, .hamstrings, .glutes, .calves]),
        ("Other", [.core, .fullBody]),
    ]
}

/// An exercise's muscle groups as one ordered, primary-first list: the
/// normalization rule and the storage codec, in one place, so the model,
/// the editor draft and the interchange can't disagree about what a list
/// means. Same shape as `MetricProfile`'s encode/decode (the app stores it
/// as an additive `Data?` column, which migrates lightweight).
public enum MuscleGroups {
    /// Primary first, no repeats, never empty. `primary` always leads,
    /// whatever order it arrived in — the group an exercise is FOR is a
    /// decision, not a side effect of tap order in one editing session.
    public static func normalized(primary: MuscleGroup, others: [MuscleGroup]) -> [MuscleGroup] {
        var seen: Set<MuscleGroup> = [primary]
        return [primary] + others.filter { seen.insert($0).inserted }
    }

    /// Normalizes a list that already carries its primary at the front,
    /// falling back to `fallback` when the list is empty (a decode miss,
    /// or a caller that cleared the selection).
    public static func normalized(_ groups: [MuscleGroup], fallback: MuscleGroup) -> [MuscleGroup] {
        guard let primary = groups.first else { return [fallback] }
        return normalized(primary: primary, others: Array(groups.dropFirst()))
    }

    /// Encodes ANY non-empty list, single groups included. A one-group
    /// list is not the same as no list: on a built-in it means the user
    /// pruned the catalog's secondaries, and dropping it would silently
    /// hand them back on the next read.
    public static func encode(_ groups: [MuscleGroup]) -> Data? {
        guard !groups.isEmpty else { return nil }
        return try? JSONEncoder().encode(groups.map(\.rawValue))
    }

    public static func decode(_ data: Data?) -> [MuscleGroup]? {
        guard let data, let raw = try? JSONDecoder().decode([String].self, from: data) else { return nil }
        let groups = raw.compactMap(MuscleGroup.init(rawValue:))
        return groups.isEmpty ? nil : groups
    }
}

public enum ExerciseType: String, Codable, Sendable {
    case weightReps
    case duration
}

/// The movement family an exercise READS as. Originally just the figure
/// icon on universal-search rows; it now also decides the Health activity
/// type a finished workout is filed under and the noun one unit of work
/// goes by (`WorkUnit`), so a wrong guess costs more than it used to —
/// but it is still DERIVED, never stored, because nothing about it is a
/// user decision.
///
/// Derivation reads gear + tracked metrics. Where those genuinely cannot
/// tell two families apart, the catalog authors an override
/// (`SeedData.BuiltInExerciseDefinition.modality`): a stretch is not a
/// plank, and a run is not a walk — both are equipment-free
/// `[distance, duration, pace]`.
public enum ExerciseModality: String, Codable, CaseIterable, Sendable {
    case strength
    /// Generic cardio — the fallback for anything that measures road or
    /// console work without naming a sport of its own.
    case cardio
    case running
    case walking
    case hiking
    case cycling
    case rowing
    case swimming
    case elliptical
    case stairClimbing
    case jumpRope
    case flexibility

    /// Whether this family is cardio at all — the one question the app
    /// asks most, and the reason `Routine.isCardio`'s old all-satisfy
    /// test on distance-or-pace was wrong (an elliptical routine tracks
    /// neither and is obviously cardio).
    public var isCardio: Bool {
        switch self {
        case .strength, .flexibility: false
        default: true
        }
    }

    /// Gear speaks first (a rower is rowing whatever it tracks), then
    /// load: anything tracking weight is strength even when it covers
    /// distance (loaded carries, sled pushes). Only then do road/console
    /// metrics (distance, pace, speed, calories) read as cardio.
    ///
    /// ⚠️ Equipment-free locomotion — running, walking, hiking, swimming —
    /// is NOT reachable here: it has no gear to key on and the same metric
    /// set as every other road effort. Those rows carry an authored
    /// modality, and derivation lands them on `.cardio`, which is wrong
    /// only in the way a fallback is allowed to be.
    public static func derive(equipmentNames: Set<String>, metrics: [WorkoutMetric]) -> ExerciseModality {
        let folded = Set(equipmentNames.map { $0.lowercased() })
        if folded.contains("rowing machine") { return .rowing }
        if folded.contains("jump rope") { return .jumpRope }
        if folded.contains("treadmill") { return .running }
        if folded.contains("elliptical") { return .elliptical }
        if !folded.isDisjoint(with: ["stair climber", "vertical climber"]) { return .stairClimbing }
        if !folded.isDisjoint(with: ["bicycle", "stationary bike", "air bike"]) { return .cycling }
        if metrics.contains(.weight) { return .strength }
        if !Set(metrics).isDisjoint(with: [.distance, .pace, .speed, .calories]) { return .cardio }
        return .strength
    }

    /// Words that should reach this exercise in a search field. The
    /// catalog carries no facet for modality, so typing is one of the two
    /// ways to find a run among two hundred lifts.
    public var searchTerms: [String] {
        switch self {
        case .strength: ["strength", "lifting", "weights"]
        case .cardio: ["cardio", "conditioning"]
        case .running: ["cardio", "running", "run"]
        case .walking: ["cardio", "walking", "walk"]
        case .hiking: ["cardio", "hiking", "hike", "trail"]
        case .cycling: ["cardio", "cycling", "bike", "biking", "ride"]
        case .rowing: ["cardio", "rowing", "row", "erg"]
        case .swimming: ["cardio", "swimming", "swim", "pool"]
        case .elliptical: ["cardio", "elliptical", "cross trainer"]
        case .stairClimbing: ["cardio", "stairs", "stair climber", "climbing"]
        case .jumpRope: ["cardio", "jump rope", "skipping"]
        case .flexibility: ["flexibility", "mobility", "stretch"]
        }
    }

    /// The short label a modality wears as a card data tag, in place of
    /// the muscle group — "Full Body" on a run says nothing true.
    public var displayName: String {
        switch self {
        case .strength: "Strength"
        case .cardio: "Cardio"
        case .running: "Running"
        case .walking: "Walking"
        case .hiking: "Hiking"
        case .cycling: "Cycling"
        case .rowing: "Rowing"
        case .swimming: "Swimming"
        case .elliptical: "Elliptical"
        case .stairClimbing: "Stairs"
        case .jumpRope: "Jump rope"
        case .flexibility: "Mobility"
        }
    }
}
