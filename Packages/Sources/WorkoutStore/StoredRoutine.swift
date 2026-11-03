import Foundation
import SwiftData

// The stored shape of a routine. The class names will be CloudKit record types once sync is
// on, so they are final now. Every rule in swiftdata.md holds: defaults or optionals, nothing
// unique, an optional relationship with an inverse.

typealias StoredRoutine = RoutineSchemaV7.StoredRoutine
typealias StoredRoutineExercise = RoutineSchemaV7.StoredRoutineExercise

/// Today's routines: V4's, with each row's rest, switch between sides, and transition, and a
/// superset's own gaps on every member. Its workouts are still V6's.
enum RoutineSchemaV7: VersionedSchema {
    static let versionIdentifier = Schema.Version(7, 0, 0)
    static var models: [any PersistentModel.Type] {
        [StoredRoutine.self, StoredRoutineExercise.self, StoredWorkout.self, StoredSet.self]
    }

    @Model
    final class StoredRoutine {
        var id = UUID()
        /// Empty when unnamed.
        var name = ""
        /// When the name or the rows last changed: the launch rule opens the latest.
        var editedAt = Date.distantPast
        /// When the routine was last opened from the drawer. Apart from `editedAt`, so an open is
        /// never mistaken for an edit; a routine's recency is the later of the two.
        var openedAt = Date.distantPast
        /// When the routine was last used: opened or edited, whichever came later.
        var recency: Date {
            max(editedAt, openedAt)
        }

        @Relationship(deleteRule: .cascade, inverse: \StoredRoutineExercise.routine)
        var exercises: [StoredRoutineExercise]? = []

        init(id: UUID) {
            self.id = id
        }
    }

    @Model
    final class StoredRoutineExercise {
        /// The row's own identity, so duplicates of an exercise stay apart.
        var id = UUID()
        /// The built-in exercise's slug, `Exercise.id`.
        var exerciseID = ""
        /// A relationship is unordered, so the row carries its place.
        var position = 0
        var routine: StoredRoutine?
        // The row's plan. Nil means never stored, read as the exercise's default: rows saved before
        // plans existed have none. Reps and seconds are apart so a stored number never changes
        // meaning if an exercise's measure does.
        var sets: Int?
        var reps: Int?
        var seconds: Int?
        var weight: Double?
        /// `WeightUnit`'s raw value; set with `weight`, or both nil.
        var weightUnit: String?
        /// The superset the row is in, shared with the rows next to it in it; nil for a plain row,
        /// and for every row saved before supersets.
        var supersetID: UUID?
        // The row's own gaps, in seconds, stored with its plan; nil for a row saved before them.
        // Kept while the row is in a superset, so leaving it brings them back.
        var rest: Int?
        /// Nil also on a row not done per side.
        var switchSides: Int?
        var transition: Int?
        // Its superset's gaps, in seconds, the same on every member; nil until set, and on a plain
        // row. `roundSwitch` is never read or written: a superset has no switch between members.
        var roundSwitch: Int?
        var roundRest: Int?
        var roundTransition: Int?

        init(id: UUID, exerciseID: String, position: Int) {
            self.id = id
            self.exerciseID = exerciseID
            self.position = position
        }
    }
}
