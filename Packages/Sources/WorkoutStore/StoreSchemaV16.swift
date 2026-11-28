import Foundation
import SwiftData

/// The second of the three: sessions and sets under their new names, and `StoredWorkout`, empty
/// since the stage into it moved every session out, now in a workout's shape, beside the
/// `StoredRoutine`s the next stage moves into it.
enum StoreSchemaV16: VersionedSchema {
    static let versionIdentifier = Schema.Version(16, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            RoutineSchemaV7.StoredRoutine.self,
            RoutineSchemaV7.StoredRoutineExercise.self,
            StoredWorkout.self,
            StoredWorkoutExercise.self,
            StoreSchemaV15.StoredWorkoutSession.self,
            StoreSchemaV15.StoredLoggedSet.self,
            StoreSchemaV15.StoredExercise.self,
            RoutineSchemaV10.StoredCustomization.self,
        ]
    }

    /// A workout, the plan: V7's `StoredRoutine`.
    @Model
    final class StoredWorkout {
        var id = UUID()
        /// Empty when unnamed.
        var name = ""
        /// When the name or the rows last changed: the launch rule opens the latest.
        var editedAt = Date.distantPast
        /// When the workout was last opened. Apart from `editedAt`, so an open is never mistaken
        /// for an edit.
        var openedAt = Date.distantPast
        /// When the workout was last used: opened or edited, whichever came later.
        var recency: Date {
            max(editedAt, openedAt)
        }

        @Relationship(deleteRule: .cascade, inverse: \StoredWorkoutExercise.workout)
        var exercises: [StoredWorkoutExercise]? = []

        init(id: UUID) {
            self.id = id
        }
    }

    /// A workout's row: V7's `StoredRoutineExercise`.
    @Model
    final class StoredWorkoutExercise {
        /// The row's own identity, so duplicates of an exercise stay apart.
        var id = UUID()
        /// The exercise's `Exercise.id`, a built-in's slug or a created exercise's id, resolved
        /// through `ExerciseList.exercise(id:)`.
        var exerciseID = ""
        /// A relationship is unordered, so the row carries its place.
        var position = 0
        var workout: StoredWorkout?
        // The row's plan. Nil means never stored, read as the exercise's default. Reps and
        // seconds are apart so a stored number never changes meaning if a measure does.
        var sets: Int?
        var reps: Int?
        var seconds: Int?
        var weight: Double?
        /// `WeightUnit`'s raw value; set with `weight`, or both nil.
        var weightUnit: String?
        /// The superset the row is in, shared with the rows next to it in it; nil for a plain
        /// row.
        var supersetID: UUID?
        /// The row's own rest after each set, in seconds: the last set by hand, kept while its
        /// rest is automatic so turning that off brings it back; nil if never set.
        var rest: Int?
        /// Whether the row's rest follows its reps or time.
        var isRestAuto = true
        /// Its superset's rest after each round, in seconds, the same on every member: the last
        /// set by hand; nil if never, and on a plain row.
        var roundRest: Int?
        /// Whether its superset's rest follows its members, the same on every member.
        var isRoundRestAuto = true

        init(id: UUID, exerciseID: String, position: Int) {
            self.id = id
            self.exerciseID = exerciseID
            self.position = position
        }
    }
}
