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
