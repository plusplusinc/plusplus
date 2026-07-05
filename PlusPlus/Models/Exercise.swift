import Foundation
import SwiftData
import PlusPlusKit

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
