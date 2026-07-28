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

/// The movement family an exercise READS as — nothing more. Drives the
/// modality figure icon on universal-search rows; derived on the fly from
/// equipment + tracked metrics, never stored (no model field, and a wrong
/// guess costs nothing — the icon is a type marker, not data).
/// `.flexibility` is authored only (the catalog's stretch/mobility rows
/// carry it as an override); derivation can't tell a stretch from a plank.
public enum ExerciseModality: String, Codable, Sendable {
    case strength
    case cardio
    case rowing
    case jumpRope
    case cycling
    case flexibility

    /// Gear speaks first (a rower is rowing whatever it tracks), then
    /// load: anything tracking weight is strength even when it covers
    /// distance (loaded carries, sled pushes). Only then do road/console
    /// metrics (distance, pace, speed, calories) read as cardio.
    public static func derive(equipmentNames: Set<String>, metrics: [WorkoutMetric]) -> ExerciseModality {
        let folded = Set(equipmentNames.map { $0.lowercased() })
        if folded.contains("rowing machine") { return .rowing }
        if folded.contains("jump rope") { return .jumpRope }
        if !folded.isDisjoint(with: ["bicycle", "stationary bike", "air bike"]) { return .cycling }
        if metrics.contains(.weight) { return .strength }
        if !Set(metrics).isDisjoint(with: [.distance, .pace, .speed, .calories]) { return .cardio }
        return .strength
    }
}
