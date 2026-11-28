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
    /// already in Log goes, each with its own dates. One asked while another is out, as from a
    /// double tap on Log's prompt or Settings' button, does nothing.
    public func askToSaveToHealth() async {
        guard await health.ask() else { return }
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
    /// the start, and nothing is read from the store unless it does. After a removal or save
    /// that fails, the access is read again, for Settings too: a failed removal, or saving no
    /// longer on, as when it is turned off mid-way, stops the run; otherwise the run goes on to
    /// the next. What wasn't saved, or came back with no id, stays owed, and the next catch-up
    /// saves it again, in place of any Health kept.
    ///
    /// First, the removals owed for workouts deleted from Log, in one call, on the same queue as
    /// the saves, so a removal never runs beside a save of the same workout. Each one's workout
    /// is gone from the store by then, so the saves can't owe it, and a save that fails never
    /// holds a removal back. A workout deleted before its turn in the saves is skipped; one
    /// deleted during its own save is removed by the catch-up its delete asked for. While saving
    /// is off they stay owed, but one whose delete never landed is still dropped.
    private func runCatchUp() async {
        // Cleared before the wait, so an ask from here on queues a run that reads after it: a
        // finish's write sent after this wait began wouldn't be in this run's read.
        isCatchUpWaiting = false
        // Each delete of these was sent before the wait below, so once it ends the store says
        // whether it landed. One sent after is noted, and the catch-up it asks for settles it.
        let removals = health.removalsToSettle()
        await loggedWorkoutWritesLanded()
        await health.refreshed()
        guard let store else { return }
        // Settled with saving off too: the store alone says which deletes landed.
        let landed = await settledRemovals(removals, in: store)
        guard health.access == .on else { return }
        if let landed {
            await makeRemovals(landed)
            // A refused removal read the access again: off, nothing would save.
            guard health.access == .on else { return }
        }
        await saveOwed(from: store)
    }

    /// Drops the removals whose delete never landed, as when the store refused it or the app
    /// closed before it, so their workout is saved as owed, and returns those whose delete
    /// landed; nil when the store didn't answer.
    private func settledRemovals(
        _ removals: [LoggedWorkout.ID],
        in store: Store,
    ) async -> [LoggedWorkout.ID]? {
        guard !removals.isEmpty else { return [] }
        do {
            return try await health.settle(
                removals,
                held: store.heldLoggedWorkouts(among: removals),
            )
        } catch {
            Logger.session.error("Which deleted workouts are gone didn't load: \(error)")
            return nil
        }
    }

    /// Makes the removals still owed of `removals`; one Health refuses stays owed for the next.
    private func makeRemovals(_ removals: [LoggedWorkout.ID]) async {
        let owed = removals.filter(health.owesRemoval(of:))
        guard !owed.isEmpty else { return }
        do {
            try await health.makeRemovals(owed)
        } catch {
            Logger.session.error("Apple Health didn't remove deleted workouts: \(error)")
            await health.refreshed()
        }
    }

    /// The saves of the run, as above.
    private func saveOwed(from store: Store) async {
        let owed: [LoggedWorkout]
        do {
            owed = try await store.owedToHealth()
        } catch {
            Logger.session.error("What Apple Health is owed didn't load: \(error)")
            return
        }
        guard !owed.isEmpty else { return }
        // One removal for the run, then saves that only add: a workout is owed only while the
        // store has no Health id for it, so everything a save of it may have left (a run killed
        // after Health's save, before its id was kept) carries a tag removed here, and a
        // workout saved with its id kept is never read as owed again. Runs go one at a time, so
        // nothing saves between the removal and this run's saves.
        do {
            try await health.remove(owed.map(\.id))
        } catch {
            Logger.session.error("Apple Health didn't remove the app's workouts: \(error)")
            await health.refreshed()
            return
        }
        for finished in owed {
            // Deleted from Log since the read: never saved.
            guard !health.owesRemoval(of: finished.id),
                  let workout = try? HealthWorkout(finished, in: exercises)
            else { continue }
            let healthID: UUID?
            do {
                healthID = try await health.save(workout)
            } catch {
                // One workout Health refuses for its own sake mustn't hold back the rest, which
                // come back in the same order every run.
                Logger.session.error("Apple Health didn't take a workout: \(error)")
                await health.refreshed()
                guard health.access == .on else { return }
                continue
            }
            guard let healthID else { continue }
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
