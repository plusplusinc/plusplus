extension Store {
    /// Where the app opens, which `launch(weightUnit:)` finds.
    public enum Launch: Equatable, Sendable {
        /// A logged workout in progress, on its workout.
        case inProgress(Workout, WorkoutSession)
        /// The workout last opened or edited, with nothing finished since.
        case workout(Workout)
        /// The Workouts list: a logged workout finished after the last open or edit.
        case workouts
        /// A new, empty workout: there is no saved one.
        case newWorkout

        /// The workout it opens on, if any: nil for the list and for a new workout.
        public var workout: Workout? {
            switch self {
            case let .inProgress(workout, _), let .workout(workout): workout
            case .workouts, .newWorkout: nil
            }
        }

        /// The logged workout in progress, if any.
        public var loggedWorkout: WorkoutSession? {
            if case let .inProgress(_, loggedWorkout) = self {
                loggedWorkout
            } else {
                nil
            }
        }
    }
}
