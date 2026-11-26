import Foundation
import SwiftData

/// As #298 shipped it: V12's, with each logged set keeping where the workout's clock stood at
/// a Skip rest tap on the rest after it, so a skip is stored as what happened, not as a cut
/// length.
enum RoutineSchemaV13: VersionedSchema {
    static let versionIdentifier = Schema.Version(13, 0, 0)
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

    /// V12's workout, holding V13's sets.
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
        // `Workout.count`: none unless the row, round, and start clock are all set.
        var countRowID: UUID?
        var countRound: Int?
        /// `Side`'s raw value; an unknown one reads as nil.
        var countSide: String?
        var countStartClock: Double?
        var countAdded = 0

        init(id: UUID) {
            self.id = id
        }
    }

    /// V12's set, with its rest's skip.
    @Model
    final class StoredSet {
        var id = UUID()
        var workout: StoredWorkout?
        var rowID: UUID?
        /// The exercise's `Exercise.id`, a built-in's slug or a created exercise's id.
        var exerciseID = ""
        /// The exercise's name when the set was logged; nil for a set logged before V9.
        var exerciseName: String?
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
        /// `LoggedSet.clockWhenLogged`; nil for a set logged before V11.
        var clockWhenLogged: Double?
        /// `LoggedSet.restAdjustment`.
        var restAdjustment = 0
        /// `LoggedSet.timeAdded`.
        var timeAdded = 0
        /// `LoggedSet.restSkippedAt`; nil for a rest not skipped, and for every set before V13.
        var restSkippedAt: Double?

        init(id: UUID) {
            self.id = id
        }
    }
}
