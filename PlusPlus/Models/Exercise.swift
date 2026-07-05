import Foundation
import SwiftData

enum MuscleGroup: String, Codable, CaseIterable, Identifiable {
    case chest, back, shoulders, biceps, triceps
    case quads, hamstrings, glutes, calves, core
    case fullBody

    var id: Self { self }

    var displayName: String {
        switch self {
        case .fullBody: "Full Body"
        default: rawValue.capitalized
        }
    }

    static let grouped: [(region: String, groups: [MuscleGroup])] = [
        ("Upper Body", [.chest, .back, .shoulders, .biceps, .triceps]),
        ("Lower Body", [.quads, .hamstrings, .glutes, .calves]),
        ("Other", [.core, .fullBody]),
    ]
}

enum ExerciseType: String, Codable {
    case weightReps
    case duration
}

@Model
final class Exercise {
    var name: String
    var muscleGroup: MuscleGroup
    @Relationship var equipment: [Equipment] = []
    var exerciseType: ExerciseType
    var isBuiltIn: Bool
    var notes: String?
    var videoURL: String?

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
