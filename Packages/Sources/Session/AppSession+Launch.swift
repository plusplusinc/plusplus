import WorkoutStore

extension AppSession {
    /// A session where the app opens (`Store.Launch`): on its workout, the logged workout in
    /// progress with it, or on the Workouts screen over a new workout after a finish. A new
    /// workout otherwise.
    public convenience init(
        launch: Store.Launch,
        exercises: ExerciseList = .builtIn,
        store: Store?,
        namer: WorkoutNamer,
    ) {
        self.init(
            workout: launch.workout ?? Workout(),
            loggedWorkout: launch.loggedWorkout,
            exercises: exercises,
            store: store,
            namer: namer,
        )
        if launch == .workouts {
            screen = .workouts
        }
    }
}
