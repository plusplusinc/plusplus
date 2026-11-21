import OSLog
import WorkoutStore

extension RoutineSession {
    /// Shows Log and closes the drawer.
    public func showLog() {
        screen = .log
        closeDrawer()
    }

    /// Pushes a finished workout onto Log, read-only.
    public func openWorkout(_ id: Workout.ID) {
        screen = .loggedWorkout(id)
    }

    /// Pops the workout pushed onto Log, as its back button and back swipe do.
    public func popWorkout() {
        if case .loggedWorkout = screen {
            screen = .log
        }
    }

    /// Reads the finished workouts again, for Log. A read that fails leaves the last one.
    public func refreshLog() async {
        guard let store else { return }
        do {
            log = try await WorkoutLog(workouts: store.finishedWorkouts())
        } catch {
            Logger.session.error("The log didn't load: \(error)")
        }
    }
}
