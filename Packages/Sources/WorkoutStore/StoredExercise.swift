import Foundation
import SwiftData

typealias StoredExercise = RoutineSchemaV8.StoredExercise

/// Today's shape: V7's routines and V6's workouts, with the exercises someone created.
enum RoutineSchemaV8: VersionedSchema {
    static let versionIdentifier = Schema.Version(8, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            StoredRoutine.self,
            StoredRoutineExercise.self,
            StoredWorkout.self,
            StoredSet.self,
            StoredExercise.self,
        ]
    }

    /// An exercise someone created: only its five settings, everything else derived on read.
    /// No relationship: a routine row names it by `id`, as it does a built-in by its slug, so
    /// rows, sets, and exercises sync as records of their own and none cascades into another.
    @Model
    final class StoredExercise {
        /// The id a row stores, `CreatedExercise.id`.
        var id = ""
        var name = ""
        /// `MuscleGroup`'s raw values, joined by commas in declaration order, as `equipment`'s
        /// are. Named for the one group V8 first held: renaming it would be a new schema
        /// version, and one group alone, "back", is the same field read the same way.
        var muscleGroup = ""
        /// `Equipment`'s raw values, joined by commas in display order (`Set.stored`).
        var equipment = ""
        /// `Measure`'s raw value.
        var measure = "reps"
        var isPerSide = false
        var createdAt = Date.distantPast

        init(id: String) {
            self.id = id
        }
    }
}

extension StoredExercise {
    /// The exercise as set, or nil for a measure this build doesn't know, or no muscle group it
    /// knows, from a newer version: left out of the list rather than read as something else. An
    /// unknown group or piece of equipment beside known ones is left out of its set.
    var created: CreatedExercise? {
        let groups = Set<MuscleGroup>(stored: muscleGroup)
        guard !groups.isEmpty, let measure = Measure(rawValue: measure) else { return nil }
        return CreatedExercise(
            id: id,
            name: name,
            muscleGroups: groups,
            equipment: Set(stored: equipment),
            measure: measure,
            isPerSide: isPerSide,
            createdAt: createdAt,
        )
    }

    /// Sets only the fields that changed, so an unchanged exercise stays clean.
    func write(_ created: CreatedExercise) {
        let groups = created.muscleGroups.stored
        let equipment = created.equipment.stored
        if name != created.name {
            name = created.name
        }
        if muscleGroup != groups {
            muscleGroup = groups
        }
        if self.equipment != equipment {
            self.equipment = equipment
        }
        if measure != created.measure.rawValue {
            measure = created.measure.rawValue
        }
        if isPerSide != created.isPerSide {
            isPerSide = created.isPerSide
        }
        if createdAt != created.createdAt {
            createdAt = created.createdAt
        }
    }
}
