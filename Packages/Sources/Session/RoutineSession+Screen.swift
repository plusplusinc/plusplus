extension RoutineSession {
    /// Where the app is, under the drawer.
    public enum Screen {
        /// The open routine, at the root: as launched, and once a workout starts.
        case routine
        /// The Routines screen, its list showing.
        case routines
        /// The open routine, pushed onto the Routines screen from its list.
        case pushedRoutine
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

    /// What the drawer marks as showing: the Routines screen, or a routine, which marks nothing.
    public var showing: Showing {
        switch screen {
        case .routines: .routines
        case .routine, .pushedRoutine: .routine
        }
    }

    public enum Showing {
        case routines
        case routine
    }
}
