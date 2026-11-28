import Foundation
import SwiftData

/// As #239 shipped it: V11's, with a workout keeping the timed set under way (its set, where its
/// count starts on the workout's clock, and its +15 s taps), and each logged set its +15 s taps,
/// so a timed set's count carries on through a relaunch.
enum RoutineSchemaV12: VersionedSchema {
    static let versionIdentifier = Schema.Version(12, 0, 0)
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

    /// V11's workout, with its count, holding V12's sets.
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

    /// V11's set, with its +15 s taps.
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

        init(id: UUID) {
            self.id = id
        }
    }
}
