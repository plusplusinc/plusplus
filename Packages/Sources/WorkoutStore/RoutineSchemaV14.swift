import Foundation
import SwiftData

/// As #301 shipped it: V13's, with a logged workout keeping each pause's times, its Apple Health
/// type as worked out at Finish, and the id of the workout Health saved for it.
enum RoutineSchemaV14: VersionedSchema {
    static let versionIdentifier = Schema.Version(14, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            RoutineSchemaV7.StoredRoutine.self,
            RoutineSchemaV7.StoredRoutineExercise.self,
            StoredWorkout.self,
            StoredSet.self,
            RoutineSchemaV8.StoredExercise.self,
            RoutineSchemaV10.StoredCustomization.self,
        ]
    }

    /// V13's workout, with its pauses, Health type, and Health id, holding V14's sets.
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
        /// `WorkoutSession.pauses`, each resumed pause's start then end, in order; nil for a
        /// workout from before V14. An odd count, or a pause ending before it starts, reads as
        /// none, and a save leaves it as it is.
        var pauseTimes: [Date]?
        /// `HealthActivity`'s raw value, worked out at Finish; nil before V14 or while in
        /// progress. An unknown one reads as nil, and a save leaves it as it is.
        var healthActivity: String?
        /// The id of the workout Apple Health saved for it. Read, never written by a save;
        /// `Store.markInHealth` writes it.
        var healthWorkoutID: UUID?

        init(id: UUID) {
            self.id = id
        }
    }

    /// V13's set, unchanged, belonging to V14's workout.
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
