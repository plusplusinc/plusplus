import WorkoutStore

extension RoutineSession {
    /// Where the app is, under the drawer.
    public enum Screen: Equatable {
        /// The open routine, at the root: as launched, and once a workout starts.
        case routine
        /// The Routines screen, its list showing.
        case routines
        /// The open routine, pushed onto the Routines screen from its list.
        case pushedRoutine
        /// Log, its tabs showing.
        case log
        /// A finished workout, pushed onto Log from its Workouts tab.
        case loggedWorkout(Workout.ID)

        /// Whether something is pushed, so the edge swipe goes back rather than opening the
        /// drawer.
        public var isPushed: Bool {
            switch self {
            case .pushedRoutine, .loggedWorkout: true
            case .routine, .routines, .log: false
            }
        }
    }

    /// Shows the Routines screen and closes the drawer.
    public func showRoutines() {
        screen = .routines
        closeDrawer()
    }

    /// Pops the routine pushed onto the Routines screen, showing the list again, as its back
    /// button and back swipe do. A push goes through `open` or `startNew`.
    public func popRoutine() {
        if screen == .pushedRoutine {
            screen = .routines
        }
    }

    /// What the drawer marks as showing: the Routines screen, Log, or a routine, which marks
    /// nothing.
    public var showing: Showing {
        switch screen {
        case .routines: .routines
        case .log, .loggedWorkout: .log
        case .routine, .pushedRoutine: .routine
        }
    }

    public enum Showing {
        case routines
        case log
        case routine
    }
}
