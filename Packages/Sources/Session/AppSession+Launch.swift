import Health
import WorkoutStore

extension AppSession {
    /// A session where the app opens (`Store.Launch`): on its workout, the workout session in
    /// progress with it, or on the Workouts screen over a new workout after a finish. A new
    /// workout otherwise.
    public convenience init(
        launch: Store.Launch,
        exercises: ExerciseList = .builtIn,
        store: Store?,
        namer: WorkoutNamer,
        health: HealthSaving,
    ) {
        self.init(
            workout: launch.workout ?? Workout(),
            workoutSession: launch.workoutSession,
            exercises: exercises,
            store: store,
            namer: namer,
            health: health,
        )
        screen = switch launch {
        case .workouts: .workouts
        case .inProgress, .workout, .newWorkout: .workout
        }
    }
}
