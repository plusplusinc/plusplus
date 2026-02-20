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

    init(
        name: String,
        muscleGroup: MuscleGroup,
        equipment: [Equipment] = [],
        exerciseType: ExerciseType = .weightReps,
        isBuiltIn: Bool = false
    ) {
        self.name = name
        self.muscleGroup = muscleGroup
        self.equipment = equipment
        self.exerciseType = exerciseType
        self.isBuiltIn = isBuiltIn
    }
}
