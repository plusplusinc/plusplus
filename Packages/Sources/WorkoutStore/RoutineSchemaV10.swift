import Foundation
import SwiftData

/// V9's, with the changes someone made to built-in exercises, stored apart from the catalog.
enum RoutineSchemaV10: VersionedSchema {
    static let versionIdentifier = Schema.Version(10, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            RoutineSchemaV7.StoredRoutine.self,
            RoutineSchemaV7.StoredRoutineExercise.self,
            RoutineSchemaV9.StoredWorkout.self,
            RoutineSchemaV9.StoredSet.self,
            RoutineSchemaV8.StoredExercise.self,
            StoredCustomization.self,
        ]
    }

    /// A built-in's customization: every setting as someone set it, and which of them count.
    /// No relationship: the built-in is a slug, as a row's `exerciseID` is.
    @Model
    final class StoredCustomization {
        /// The built-in's slug.
        var exerciseID = ""
        /// `Customization.Setting`'s raw values, joined by commas: the settings that count.
        var changed = ""
        var name = ""
        /// `MuscleGroup`'s raw values, joined by commas (`Set.stored`).
        var muscleGroups = ""
        /// `Equipment`'s raw values, joined by commas (`Set.stored`).
        var equipment = ""
        /// `Measure`'s raw value.
        var measure = "reps"
        var isPerSide = false
        /// When it last changed, so the latest wins if sync leaves two for one built-in.
        var editedAt = Date.distantPast

        init(exerciseID: String) {
            self.exerciseID = exerciseID
        }
    }
}
