import Foundation
import Health
import Testing
@testable import Session
@testable import WorkoutStore

/// Deleting a workout from Log takes it out of Apple Health: the removal is owed on the device
/// from before the delete is sent, made by a catch-up after its saves, and never lets a
/// deleted workout be saved. A relaunch is a second session over the same store and defaults.
@Suite("Apple Health delete")
struct HealthDeleteTests {
    private let fixture: HealthFixture

    init() throws {
        fixture = try HealthFixture()
    }

    /// A session over the store whose log is read, as Log shows it.
    private func showingLog(_ health: FakeHealth) async -> AppSession {
        let session = fixture.launched(health)
        await session.refreshLog()
        return session
    }

    /// `finished`, saved to Health by a catch-up, with its Health id.
    private func inHealth(_ finished: LoggedWorkout, _ health: FakeHealth) async throws -> UUID {
        await fixture.launched(health).caughtUpHealth()
        return try #require(health.inHealth.withLock { $0[finished.id] })
    }

    @Test("A workout in Health deleted from Log leaves Health, by its tag and Health's id")
    func deleteRemoves() async throws {
        let deleted = try await fixture.seedFinished(100, 200)
        let kept = try await fixture.seedFinished(300, 400)
        let health = FakeHealth(.on)
        let healthID = try await inHealth(deleted, health)
        let session = await showingLog(health)
        await session.deleteLoggedWorkout(deleted.id)
        await session.healthJobsLanded()
        #expect(session.log?.loggedWorkouts.map(\.id) == [kept.id])
        #expect(health.inHealth.withLock { $0.keys.sorted() } == [kept.id])
        #expect(health.removals.withLock { $0.last } == [deleted.id])
        #expect(health.removedHealthIDs.withLock { $0.last } == [healthID])
        #expect(session.health.removalsOwed.isEmpty)
    }

    @Test("A removal Health refuses stays owed and is made at the next catch-up")
    func refusedRemovalRetried() async throws {
        let deleted = try await fixture.seedFinished(100, 200)
        let health = FakeHealth(.on)
        _ = try await inHealth(deleted, health)
        let session = await showingLog(health)
        health.refusesRemovals.withLock { $0 = true }
        await session.deleteLoggedWorkout(deleted.id)
        await session.healthJobsLanded()
        #expect(session.log?.loggedWorkouts == [])
        #expect(health.inHealth.withLock { $0[deleted.id] } != nil)
        health.refusesRemovals.withLock { $0 = false }
        await session.caughtUpHealth()
        #expect(health.inHealth.withLock { $0.isEmpty })
        #expect(session.health.removalsOwed.isEmpty)
    }

    @Test("Deleted with saving off, the workout leaves Log, and a relaunch with it on removes it")
    func offThenRelaunchRemoves() async throws {
        let deleted = try await fixture.seedFinished(100, 200)
        let health = FakeHealth(.on)
        _ = try await inHealth(deleted, health)
        health.access.withLock { $0 = .off }
        let removalsBefore = health.removals.withLock { $0.count }
        let session = await showingLog(health)
        await session.deleteLoggedWorkout(deleted.id)
        await session.healthJobsLanded()
        #expect(session.log?.loggedWorkouts == [])
        #expect(try await fixture.store().finishedLoggedWorkouts().isEmpty)
        #expect(health.removals.withLock { $0.count } == removalsBefore)
        health.access.withLock { $0 = .on }
        await fixture.launched(health).caughtUpHealth()
        #expect(health.inHealth.withLock { $0.isEmpty })
        await fixture.launched(health).caughtUpHealth()
        #expect(health.removals.withLock { $0.count } == removalsBefore + 1)
    }

    @Test("Never asked, a delete leaves Log and asks Health for no removal")
    func notAskedRemovesNothing() async throws {
        let deleted = try await fixture.seedFinished(100, 200)
        let health = FakeHealth(.notAsked)
        let session = await showingLog(health)
        await session.deleteLoggedWorkout(deleted.id)
        await session.healthJobsLanded()
        #expect(session.log?.loggedWorkouts == [])
        #expect(health.removals.withLock { $0.isEmpty })
        #expect(health.attempts.withLock { $0.isEmpty })
    }

    @Test("A workout still owed to Health when deleted is never saved, saving turned on after")
    func deletedWhileOwedNeverSaved() async throws {
        let deleted = try await fixture.seedFinished(100, 200)
        let health = FakeHealth(.off)
        let session = await showingLog(health)
        await session.deleteLoggedWorkout(deleted.id)
        await session.healthJobsLanded()
        health.access.withLock { $0 = .on }
        await session.caughtUpHealth()
        await fixture.launched(health).caughtUpHealth()
        #expect(health.attempts.withLock { $0.isEmpty })
        #expect(health.inHealth.withLock { $0.isEmpty })
    }

    @Test("A workout deleted mid-way through a catch-up, before its turn, is never saved")
    func deletedBeforeItsTurn() async throws {
        let first = try await fixture.seedFinished(100, 200)
        let deleted = try await fixture.seedFinished(300, 400)
        let health = FakeHealth(.on)
        let session = await showingLog(health)
        health.holdsNext.withLock { $0 = true }
        session.catchUpHealth()
        await health.saveHeld()
        await session.deleteLoggedWorkout(deleted.id)
        health.release()
        await session.healthJobsLanded()
        #expect(health.attempts.withLock { $0 } == [first.id])
        #expect(health.inHealth.withLock { $0.keys.sorted() } == [first.id])
    }

    @Test("A workout deleted during its own save ends removed, and is never saved again")
    func deletedDuringItsSave() async throws {
        let deleted = try await fixture.seedFinished(100, 200)
        let health = FakeHealth(.on)
        let session = await showingLog(health)
        health.holdsNext.withLock { $0 = true }
        session.catchUpHealth()
        await health.saveHeld()
        await session.deleteLoggedWorkout(deleted.id)
        health.release()
        await session.healthJobsLanded()
        #expect(health.inHealth.withLock { $0.isEmpty })
        await fixture.launched(health).caughtUpHealth()
        #expect(health.attempts.withLock { $0 } == [deleted.id])
        #expect(session.health.removalsOwed.isEmpty)
    }

    @Test("A delete the store refuses, of the workout in progress, owes no removal, and it saves")
    func refusedDeleteStaysOwed() async throws {
        let workout = try workoutOfOne()
        let health = FakeHealth(.on)
        let session = fixture.launched(health, workout: workout)
        session.start(on: workout.id, at: HealthFixture.at(10))
        let logged = try #require(session.loggedWorkout)
        await session.deleteLoggedWorkout(logged.id)
        await session.healthJobsLanded()
        #expect(health.removals.withLock { $0.isEmpty })
        #expect(session.health.removalsOwed.isEmpty)
        session.finish(at: HealthFixture.at(70))
        await session.healthJobsLanded()
        #expect(health.inHealth.withLock { $0.keys.sorted() } == [logged.id])
    }

    @Test("Discarding a workout in progress asks Health for nothing")
    func discardAsksNothing() async throws {
        let workout = try workoutOfOne()
        let health = FakeHealth(.on)
        let session = fixture.launched(health, workout: workout)
        session.start(on: workout.id, at: HealthFixture.at(10))
        session.discard()
        await session.writesLanded()
        await session.healthJobsLanded()
        #expect(health.removals.withLock { $0.isEmpty })
        #expect(health.accessReads.withLock { $0 } == 0)
        #expect(session.health.removalsOwed.isEmpty)
    }

    @Test("Removals owed outlive the session in the device's defaults, the newest 100 kept")
    func owedKeptOnDevice() {
        let saving = HealthSaving(client: .unavailable, defaults: fixture.defaults)
        let ids = (0 ... HealthSaving.removalsKept).map { _ in UUID() }
        let healthID = UUID()
        for id in ids {
            saving.oweRemoval(of: id, healthID: id == ids.last ? healthID : nil)
        }
        let relaunched = HealthSaving(client: .unavailable, defaults: fixture.defaults)
        #expect(relaunched.removalsOwed.map(\.id) == Array(ids.dropFirst()))
        #expect(relaunched.removalsOwed.last?.healthID == healthID)
        relaunched.forgetRemovals(of: Set(ids))
        #expect(HealthSaving(client: .unavailable, defaults: fixture.defaults).removalsOwed
            .isEmpty)
    }

    private func workoutOfOne() throws -> Workout {
        let exercise = try #require(Exercise.builtIn(id: "barbell-bench-press"))
        return Workout(
            name: "Upper",
            exercises: [WorkoutExercise(exercise: exercise, weightUnit: .pounds)],
        )
    }
}
