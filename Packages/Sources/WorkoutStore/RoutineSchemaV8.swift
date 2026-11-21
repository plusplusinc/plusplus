import Foundation
import SwiftData

/// V7's routines and V6's workouts, with the exercises someone created. Its exercises are still
/// today's.
enum RoutineSchemaV8: VersionedSchema {
    static let versionIdentifier = Schema.Version(8, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            StoredRoutine.self,
            StoredRoutineExercise.self,
            RoutineSchemaV6.StoredWorkout.self,
            RoutineSchemaV6.StoredSet.self,
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
