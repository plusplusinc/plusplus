import Foundation
import SwiftData

/// The first of three versions that rename the stored models, which SwiftData can't do in
/// place: a model renamed by inference opens with none of its rows. V14's, with an empty
/// `StoredWorkoutSession` and `StoredLoggedSet` beside the `StoredWorkout`s and `StoredSet`s
/// the next stage moves into them, and a created exercise's `muscleGroup` renamed in place.
enum StoreSchemaV15: VersionedSchema {
    static let versionIdentifier = Schema.Version(15, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            RoutineSchemaV7.StoredRoutine.self,
            RoutineSchemaV7.StoredRoutineExercise.self,
            RoutineSchemaV14.StoredWorkout.self,
            RoutineSchemaV14.StoredSet.self,
            StoredWorkoutSession.self,
            StoredLoggedSet.self,
            StoredExercise.self,
            RoutineSchemaV10.StoredCustomization.self,
        ]
    }

    /// One time through a workout: V14's `StoredWorkout`, its workout's id and name renamed to
    /// match. Its workout is an id, not a relationship, so deleting the workout leaves it. No
    /// status: running, paused, and finished follow from the dates.
    @Model
    final class StoredWorkoutSession {
        var id = UUID()
        var workoutID: UUID?
        var workoutName = ""
        var startedAt = Date.distantPast
        var pausedAt: Date?
        var pausedSeconds = 0.0
        var endedAt: Date?
        @Relationship(deleteRule: .cascade, inverse: \StoredLoggedSet.workoutSession)
        var sets: [StoredLoggedSet]? = []
        // `Workout.count`: none unless the row, round, and start clock are all set.
        var countRowID: UUID?
        var countRound: Int?
        /// `Side`'s raw value; an unknown one reads as nil.
        var countSide: String?
        var countStartClock: Double?
        var countAdded = 0
        /// `WorkoutSession.pauses`, each resumed pause's start then end, in order; nil for a
        /// session from before V14. An odd count, or a pause ending before it starts, reads as
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

    /// A set done in a session: V14's `StoredSet`. Its row is an id, and its exercise a slug,
    /// so a set reads the same once its row is deleted.
    @Model
    final class StoredLoggedSet {
        var id = UUID()
        var workoutSession: StoredWorkoutSession?
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

    /// An exercise someone created: V8's, its muscle groups' field renamed in place. No
    /// relationship: a row names it by `id`, as it does a built-in by its slug.
    @Model
    final class StoredExercise {
        /// The id a row stores, `CreatedExercise.id`.
        var id = ""
        var name = ""
        /// `MuscleGroup`'s raw values, joined by commas in declaration order, as `equipment`'s
        /// are.
        @Attribute(originalName: "muscleGroup")
        var muscleGroups = ""
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
