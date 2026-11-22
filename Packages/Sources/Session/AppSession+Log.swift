import OSLog
import WorkoutStore

extension AppSession {
    /// Shows Log and closes the drawer.
    public func showLog() {
        endThroughDrawer()
        screen = .log
        closeDrawer()
    }

    /// Pushes a finished logged workout onto Log, read-only.
    public func openLoggedWorkout(_ id: LoggedWorkout.ID) {
        screen = .loggedWorkout(id)
    }

    /// Pops the logged workout pushed onto Log, as its back button and back swipe do.
    public func popLoggedWorkout() {
        if case .loggedWorkout = screen {
            screen = .log
        }
    }

    /// Reads the finished logged workouts again, for Log. A read that fails leaves the last one.
    public func refreshLog() async {
        guard let store else { return }
        do {
            log = try await WorkoutLog(loggedWorkouts: store.finishedLoggedWorkouts())
        } catch {
            Logger.session.error("The log didn't load: \(error)")
        }
    }
}
