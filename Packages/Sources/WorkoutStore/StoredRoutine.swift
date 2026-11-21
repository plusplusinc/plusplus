/// The stored shape of a workout. The class names will be CloudKit record types once sync is
/// on, so they are final now. Every rule in swiftdata.md holds: defaults or optionals, nothing
/// unique, an optional relationship with an inverse. `Workout` is stored as `StoredRoutine` and
/// `LoggedWorkout` as `StoredWorkout`: names kept from before 2026-11-21, which renaming an
/// entity would lose on a phone, until a card of their own decides them.
typealias StoredRoutine = RoutineSchemaV7.StoredRoutine
typealias StoredRoutineExercise = RoutineSchemaV7.StoredRoutineExercise
