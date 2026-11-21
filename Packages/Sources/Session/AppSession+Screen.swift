extension AppSession {
    /// Where the app is, under the drawer.
    public enum Screen {
        /// The open routine, at the root: as launched, and once a workout starts.
        case workout
        /// The Routines screen, its list showing.
        case workouts
        /// The open routine, pushed onto the Routines screen from its list.
        case pushedWorkout
    }

    /// Shows the Routines screen and closes the drawer.
    public func showWorkouts() {
        screen = .workouts
        closeDrawer()
    }

    /// Pops the routine pushed onto the Routines screen, showing the list again, as its back
    /// button and back swipe do. A push goes through `open` or `startNew`.
    public func popWorkout() {
        if screen == .pushedWorkout {
            screen = .workouts
        }
    }

    /// What the drawer marks as showing: the Routines screen, or a routine, which marks nothing.
    public var showing: Showing {
        switch screen {
        case .workouts: .workouts
        case .workout, .pushedWorkout: .workout
        }
    }

    public enum Showing {
        case workouts
        case workout
    }
}
