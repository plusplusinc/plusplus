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
    /// app comes back to the front.
    public func catchUpHealth() {
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
    /// its id kept once Health hands one back. A workout deleted from Log since the read is
    /// skipped. Whether the system lets the app is read before each, so saving turned off
    /// mid-way stops it. A save that fails, or comes back with no id, leaves the workout owed:
    /// the next catch-up saves it again, in place of any Health kept.
    private func runCatchUp() async {
        // Cleared before the wait: a delete sent before this point lands before the read.
        deletedFromLog = []
        await loggedWorkoutWritesLanded()
        health.refresh()
        guard health.access == .on, let store else { return }
        let owed: [LoggedWorkout]
        do {
            owed = try await store.owedToHealth()
        } catch {
            Logger.session.error("What Apple Health is owed didn't load: \(error)")
            return
        }
        for finished in owed where !deletedFromLog.contains(finished.id) {
            guard let workout = try? HealthWorkout(finished, in: exercises) else { continue }
            guard let healthID = await health.save(workout) else {
                guard health.access == .on else { return }
                continue
            }
            do {
                try await store.markInHealth(finished.id, as: healthID)
            } catch {
                Logger.session.error("A workout's Apple Health id didn't save: \(error)")
            }
        }
    }

    /// Returns once every Health job asked for so far has run. For tests.
    func healthJobsLanded() async {
        await withCheckedContinuation { done in healthJobs.yield(.landed(done)) }
    }
}
