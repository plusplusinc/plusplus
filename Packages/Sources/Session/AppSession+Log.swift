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
    /// workout's writes, so an End still landing can't bring it back. The store refuses the one
    /// in progress. A delete that fails is logged, and the read leaves the workout listed.
    ///
    /// Deleted from Log means removed from Apple Health, and this is where that rule lives:
    /// `Store.deleteLoggedWorkout(_:)` knows nothing of Health. The removal is owed from before
    /// the delete is sent, on the device, so a relaunch still makes it, and a catch-up still to
    /// save the workout skips it; the catch-up asked here makes it, by the workout's tag, or
    /// drops it if the delete never landed. Nothing waits on Health, and nothing it answers
    /// shows.
    public func deleteLoggedWorkout(_ id: LoggedWorkout.ID) async {
        health.oweRemoval(of: id)
        loggedWorkoutWrites.yield(.delete(id))
        catchUpHealth()
        await refreshLog()
    }

    /// What Log shows above its calendar about Apple Health: a note while one shows
    /// (`HealthSaving.note`); else the prompt to sync while offered (`HealthSaving.isOffered`),
    /// and only while Log holds a finished workout, as it asks to sync the workouts there. With
    /// the last one deleted the prompt goes, and comes back with the next finish unless
    /// dismissed; the offer itself is kept.
    public var healthPrompt: HealthPrompt? {
        if let note = health.note {
            return .note(note)
        }
        guard health.isOffered, log?.loggedWorkouts.isEmpty == false else { return nil }
        return .ask
    }

    /// The prompt's green button: Apple's sheet, then the catch-up as any ask
    /// (`askToSaveToHealth()`). Answered Don't Allow, the prompt's note for it takes its place;
    /// allowed, the prompt goes as the access is read; left unanswered, it stays.
    public func syncFromPrompt() async {
        await askToSaveToHealth()
        if health.access == .off {
            health.noteDenied()
        }
    }
}

/// Log's Apple Health line above its calendar (`AppSession.healthPrompt`).
public enum HealthPrompt: Equatable, Sendable {
    /// "Sync to Apple Health", with its ×.
    case ask
    /// Where syncing can be turned on later, until OK.
    case note(HealthSaving.Note)
}

extension AppSession {
    /// Log has taken the workout just finished, to bring it into History itself.
    public func takeJustFinished() {
        justFinished = nil
    }

    /// Reads the finished logged workouts again, for Log, once the logged workout's writes have
    /// landed, so a Log shown just after a finish lists it. A read that fails leaves the last one.
    public func refreshLog() async {
        await loggedWorkoutWritesLanded()
        guard let store else { return }
        do {
            log = try await WorkoutLog(loggedWorkouts: store.finishedLoggedWorkouts())
        } catch {
            Logger.session.error("The log didn't load: \(error)")
        }
    }
}
