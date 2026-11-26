import Foundation
import OSLog
import WorkoutStore

/// Saving to Apple Health what it is owed: every finished workout in the store it has no id
/// for (`Store.owedToHealth()`), so a finish whose save never happened, as with the app closed
/// right after it, and every workout already in Log when saving is turned on, go at the next
/// catch-up. Catch-ups run one at a time, in the order asked, so no workout is ever saved twice
/// at once.
extension AppSession {
    enum HealthJob {
        case catchUp
        /// Every job before it has run.
        case landed(CheckedContinuation<Void, Never>)
    }

    /// Saves to Health what it is owed, with saving on, once every logged workout write sent
    /// before it has landed: at launch, after a finish, after the person allows it, and as the
    /// app comes back to the front. One already queued and not yet started covers this ask, so
    /// nothing more is queued.
    public func catchUpHealth() {
        guard !isCatchUpWaiting else { return }
        isCatchUpWaiting = true
        healthJobs.yield(.catchUp)
    }

    /// Brings up Apple's sheet, then, once it is answered, catches up: allowed, every workout
    /// already in Log goes, each with its own dates.
    public func askToSaveToHealth() async {
        await health.ask()
        catchUpHealth()
    }

    /// Runs Health's jobs one at a time, each to its end before the next, for as long as the
    /// session lives.
    func startHealthJobs() -> AsyncStream<HealthJob>.Continuation {
        let (jobs, continuation) = AsyncStream.makeStream(
            of: HealthJob.self,
            bufferingPolicy: .unbounded,
        )
        Task { [weak self] in
            for await job in jobs {
                switch job {
                case .catchUp: await self?.runCatchUp()
                case let .landed(done): done.resume()
                }
            }
        }
        return continuation
    }

    /// Each owed workout, the earliest finished first, saved from what the store keeps of it,
    /// its id kept once Health hands one back. Whether the system lets the app is read once, at
    /// the start, and nothing is read from the store unless it does. A removal or save that
    /// fails, as when saving is turned off mid-way, stops the run, the access read again for
    /// Settings: what wasn't saved, or came back with no id, stays owed, and the next catch-up
    /// saves it again, in place of any Health kept.
    private func runCatchUp() async {
        // Cleared before the wait, so an ask from here on queues a run that reads after it: a
        // finish's write sent after this wait began wouldn't be in this run's read.
        isCatchUpWaiting = false
        await loggedWorkoutWritesLanded()
        await health.refreshed()
        guard health.access == .on, let store else { return }
        let owed: [LoggedWorkout]
        do {
            owed = try await store.owedToHealth()
        } catch {
            Logger.session.error("What Apple Health is owed didn't load: \(error)")
            return
        }
        guard !owed.isEmpty else { return }
        do {
            // One removal for the run, then saves that only add: a workout is owed only while
            // the store has no Health id for it, so everything a save of it may have left (a
            // run killed after Health's save, before its id was kept) carries a tag removed
            // here, and a workout saved with its id kept is never read as owed again. Runs go one
            // at a time, so nothing saves between the removal and this run's saves.
            try await health.remove(owed.map(\.id))
            for finished in owed {
                guard let workout = try? HealthWorkout(finished, in: exercises),
                      let healthID = try await health.save(workout) else { continue }
                do {
                    try await store.markInHealth(finished.id, as: healthID)
                } catch {
                    Logger.session.error("A workout's Apple Health id didn't save: \(error)")
                }
            }
        } catch {
            Logger.session.error("Apple Health didn't take a workout: \(error)")
            await health.refreshed()
        }
    }

    /// Returns once every Health job asked for so far has run. For tests.
    func healthJobsLanded() async {
        await withCheckedContinuation { done in healthJobs.yield(.landed(done)) }
    }
}
