import Foundation
import SwiftData

typealias StoredCustomization = RoutineSchemaV10.StoredCustomization

/// Today's shape: V9's, with the changes someone made to built-in exercises, stored apart from
/// the catalog.
enum RoutineSchemaV10: VersionedSchema {
    static let versionIdentifier = Schema.Version(10, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            StoredRoutine.self,
            StoredRoutineExercise.self,
            StoredWorkout.self,
            StoredSet.self,
            StoredExercise.self,
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

extension StoredCustomization {
    /// The customization as set. A setting this build can't read, from a newer version (an
    /// unknown measure, or muscle groups none of which it knows), reads as shipped; an unknown
    /// group or piece of equipment beside known ones is left out of its set.
    var customization: Customization {
        var changed = Set<Customization.Setting>(stored: changed)
        let groups = Set<MuscleGroup>(stored: muscleGroups)
        if groups.isEmpty != muscleGroups.isEmpty {
            changed.remove(.muscleGroups)
        }
        let measure = Measure(rawValue: measure)
        if measure == nil {
            changed.remove(.measure)
        }
        return Customization(
            exerciseID: exerciseID,
            settings: ExerciseSettings(
                name: name,
                muscleGroups: groups,
                equipment: Set(stored: equipment),
                measure: measure ?? .reps,
                isPerSide: isPerSide,
            ),
            changed: changed,
        )
    }

    /// Sets only the fields that changed, so an unchanged customization stays clean.
    func write(_ customization: Customization, at date: Date) {
        let settings = customization.settings
        let before = (changed, name, muscleGroups, equipment, measure, isPerSide)
        update(\.changed, to: customization.changed.stored)
        update(\.name, to: settings.name)
        update(\.muscleGroups, to: settings.muscleGroups.stored)
        update(\.equipment, to: settings.equipment.stored)
        update(\.measure, to: settings.measure.rawValue)
        update(\.isPerSide, to: settings.isPerSide)
        if before != (changed, name, muscleGroups, equipment, measure, isPerSide) {
            editedAt = date
        }
    }
}
