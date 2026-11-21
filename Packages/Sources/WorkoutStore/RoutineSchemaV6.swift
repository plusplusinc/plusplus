import Foundation
import SwiftData

/// As #127 shipped it, with logged sets, its routines still V4's.
enum RoutineSchemaV6: VersionedSchema {
    static let versionIdentifier = Schema.Version(6, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            RoutineSchemaV4.StoredRoutine.self,
            RoutineSchemaV4.StoredRoutineExercise.self,
            StoredWorkout.self,
            StoredSet.self,
        ]
    }

    /// The stored shape of a workout. Its routine is an id, not a relationship, so deleting the
    /// routine leaves the workout. No status: running, paused, and finished follow from the
    /// dates, and a discarded workout is deleted, its sets with it.
    @Model
    final class StoredWorkout {
        var id = UUID()
        var routineID: UUID?
        var routineName = ""
        var startedAt = Date.distantPast
        var pausedAt: Date?
        var pausedSeconds = 0.0
        var endedAt: Date?
        @Relationship(deleteRule: .cascade, inverse: \StoredSet.workout)
        var sets: [StoredSet]? = []

        init(id: UUID) {
            self.id = id
        }
    }

    /// A set done in a workout: its numbers as done, and as planned, apart. Its row is an id, and
    /// its exercise a slug, so a set reads the same once its row is deleted.
    @Model
    final class StoredSet {
        var id = UUID()
        var workout: StoredWorkout?
        var rowID: UUID?
        /// The exercise's `Exercise.id`, a built-in's slug or a created exercise's id.
        var exerciseID = ""
        /// The order it was logged in: a relationship is unordered.
        var position = 0
        var round = 0
        /// `Side`'s raw value; nil for an exercise not done per side, and an unknown one reads
        /// as nil.
        var side: String?
        // As done. Reps and seconds are apart, as on a row, so a number never changes meaning.
        var reps: Int?
        var seconds: Int?
        var weight: Double?
        /// `WeightUnit`'s raw value; set with `weight`, or both nil.
        var weightUnit: String?
        // As planned when it was logged.
        var plannedReps: Int?
        var plannedSeconds: Int?
        var plannedWeight: Double?
        var plannedWeightUnit: String?
        var loggedAt = Date.distantPast

        init(id: UUID) {
            self.id = id
        }
    }
}
