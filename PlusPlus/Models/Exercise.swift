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
    /// Personal-library membership (v2 Library, #63). Built-ins default
    /// to true so existing stores show everything until the user prunes;
    /// removing a built-in from the library sets this false (the catalog
    /// keeps it). Customs are always in the library.
    var inLibrary: Bool = true
    var notes: String?
    var videoURL: String?

    /// The per-tap weight increment this exercise's gear implies: the
    /// smallest override among its equipment (microplates win over a
    /// pin stack when both are involved), nil when none is set.
    /// isDeleted guard mirrors ExerciseFilterState (bug hunt B1).
    var weightStepOverride: Double? {
        equipment.filter { !$0.isDeleted }.compactMap(\.weightStep).min()
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
