extension RoutineSession {
    /// Where the app is, under the drawer.
    public enum Screen {
        /// The open routine, at the root.
        case routine
        /// The Routines screen, its list showing.
        case routines
        /// The open routine, pushed onto the Routines screen from its list.
        case pushedRoutine
        /// Exercises, at the root as Routines is. The open routine and its workout stay as they
        /// were, to show again when the drawer opens the routine.
        case exercises
    }

    /// Shows the Routines screen and closes the drawer.
    public func showRoutines() {
        screen = .routines
        closeDrawer()
    }

    /// Shows Exercises in place of the screen showing and closes the drawer.
    public func showExercises() {
        screen = .exercises
        closeDrawer()
    }

    /// Pops the routine pushed onto the Routines screen, showing the list again, as its back
    /// button and back swipe do. A push goes through `open` or `startNew`.
    public func popRoutine() {
        if screen == .pushedRoutine {
            screen = .routines
        }
    }

    /// What the drawer marks as showing: the Routines screen, Exercises, the open routine, or a
    /// new one.
    public var showing: Showing {
        switch screen {
        case .routines: .routines
        case .exercises: .exercises
        case .routine, .pushedRoutine: current.isEmpty ? .new : .routine
        }
    }

    public enum Showing {
        case routines
        case exercises
        case routine
        case new
    }
}
