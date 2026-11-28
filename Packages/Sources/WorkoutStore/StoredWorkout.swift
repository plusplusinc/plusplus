/// The stored shape of a workout, `Workout`, and of its rows. The class names will be CloudKit
/// record types once sync is on, so they are final now. Every rule in swiftdata.md holds:
/// defaults or optionals, nothing unique, an optional relationship with an inverse. Before
/// V17 a workout was stored as `StoredRoutine`, and before V16 `StoredWorkout` held a session.
typealias StoredWorkout = StoreSchemaV16.StoredWorkout
typealias StoredWorkoutExercise = StoreSchemaV16.StoredWorkoutExercise
