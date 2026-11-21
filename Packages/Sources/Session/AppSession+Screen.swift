import WorkoutStore

extension AppSession {
    /// Where the app is, under the drawer.
    public enum Screen: Equatable {
        /// The open workout, at the root: as launched, and once it starts.
        case workout
        /// The Workouts screen, its list showing.
        case workouts
        /// The open workout, pushed onto the Workouts screen from its list.
        case pushedWorkout
        /// Log, its tabs showing.
        case log
        /// A finished logged workout, pushed onto Log from its History tab.
        case loggedWorkout(LoggedWorkout.ID)

        /// Whether something is pushed, so the edge swipe goes back rather than opening the
        /// drawer.
        public var isPushed: Bool {
            switch self {
            case .pushedWorkout, .loggedWorkout: true
            case .workout, .workouts, .log: false
            }
        }
    }

    /// Shows the Workouts screen and closes the drawer.
    public func showWorkouts() {
        screen = .workouts
        closeDrawer()
    }

    /// Pops the workout pushed onto the Workouts screen, showing the list again, as its back
    /// button and back swipe do. A push goes through `open` or `startNew`.
    public func popWorkout() {
        if screen == .pushedWorkout {
            screen = .workouts
        }
    }

    /// What the drawer marks as showing: the Workouts screen, Log, or a workout, which marks
    /// nothing.
    public var showing: Showing {
        switch screen {
        case .workouts: .workouts
        case .log, .loggedWorkout: .log
        case .workout, .pushedWorkout: .workout
        }
    }

    public enum Showing {
        case workouts
        case log
        case workout
    }
}
