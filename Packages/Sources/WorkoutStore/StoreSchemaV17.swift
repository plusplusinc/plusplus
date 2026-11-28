import SwiftData

/// The last of the three, and the renamed shape: V16's without the `StoredRoutine`s and their
/// rows, which the stage into it moved into `StoredWorkout` and `StoredWorkoutExercise`.
enum StoreSchemaV17: VersionedSchema {
    static let versionIdentifier = Schema.Version(17, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            StoreSchemaV16.StoredWorkout.self,
            StoreSchemaV16.StoredWorkoutExercise.self,
            StoreSchemaV15.StoredWorkoutSession.self,
            StoreSchemaV15.StoredLoggedSet.self,
            StoreSchemaV15.StoredExercise.self,
            RoutineSchemaV10.StoredCustomization.self,
        ]
    }
}
