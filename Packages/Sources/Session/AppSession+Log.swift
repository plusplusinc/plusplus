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

    /// Deletes a finished logged workout and its sets, from Log's History, then reads the log
    /// again, so its count, calendar, Diff, and Balance follow. Queued behind the logged
    /// workout's writes, so an End still landing can't bring it back. Refused for the one in
    /// progress. A delete that fails is logged, and the read leaves the workout listed.
    public func deleteLoggedWorkout(_ id: LoggedWorkout.ID) async {
        guard loggedWorkout?.id != id else { return }
        loggedWorkoutWrites.yield(.delete(id))
        await withCheckedContinuation { done in loggedWorkoutWrites.yield(.landed(done)) }
        await refreshLog()
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
