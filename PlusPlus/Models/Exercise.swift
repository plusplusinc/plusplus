import Foundation
import SwiftData
import PlusPlusKit

@Model
final class Exercise {
    var name: String
    var muscleGroup: MuscleGroup
    @Relationship(inverse: \Equipment.exercises) var equipment: [Equipment] = []
    var exerciseType: ExerciseType
    var isBuiltIn: Bool
    /// Personal-library membership (v2 Library, #63). Built-ins default
    /// to true so existing stores show everything until the user prunes;
    /// removing a built-in from the library sets this false (the catalog
    /// keeps it). Customs are always in the library.
    var inLibrary: Bool = true
    var notes: String?
    var videoURL: String?
    /// Default targets (#187): what a fresh routine entry starts from.
    /// nil falls back to the metric's global default (10 reps / 45 s).
    /// Routine edits bump these — the latest prescription anywhere IS
    /// the new default — and the editor exposes them directly.
    var defaultWeight: Double?
    var defaultReps: Int?
    var defaultRepsUpper: Int?
    var defaultDurationSeconds: Int?

    var hasDefaultTargets: Bool {
        defaultWeight != nil || defaultReps != nil
            || defaultRepsUpper != nil || defaultDurationSeconds != nil
    }

    /// The per-tap weight increment this exercise's gear implies: the
    /// smallest override among its LOADABLE equipment (microplates win
    /// over a pin stack when both are involved), nil when none is set.
    /// Non-loadable gear is skipped, not migrated (#236): pre-build-32
    /// stores can carry a step on a Bench from when every screen
    /// offered one — the card is gated now, so honoring that value
    /// would wedge stepping with no UI left to reveal or clear it.
    /// isDeleted guard mirrors ExerciseFilterState (bug hunt B1).
    var weightStepOverride: Double? {
        equipment
            .filter { !$0.isDeleted && SeedData.isLoadable($0) }
            .compactMap(\.weightStep).min()
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
