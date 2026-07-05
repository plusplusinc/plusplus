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
