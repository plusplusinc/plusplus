import Foundation
import Health
import Testing
@testable import Session
@testable import WorkoutStore

/// Deleting a workout from Log takes it out of Apple Health: the removal is owed on the device
/// from before the delete is sent, made by a catch-up before its saves, and never lets a
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

    /// `finished`, saved to Health by a catch-up.
    private func inHealth(_ finished: WorkoutSession, _ health: FakeHealth) async throws {
        await fixture.launched(health).caughtUpHealth()
        try #require(health.inHealth.withLock { $0.contains(finished.id) })
    }

    @Test("A workout in Health deleted from Log leaves Health, by its tag")
    func deleteRemoves() async throws {
        let deleted = try await fixture.seedFinished(100, 200)
        let kept = try await fixture.seedFinished(300, 400)
        let health = FakeHealth(.on)
        try await inHealth(deleted, health)
        let session = await showingLog(health)
        await session.deleteWorkoutSession(deleted.id)
        await session.healthJobsLanded()
        #expect(session.log?.workoutSessions.map(\.id) == [kept.id])
        #expect(health.inHealth.withLock { $0 } == [kept.id])
        #expect(health.removals.withLock { $0.last } == [deleted.id])
        #expect(session.health.removalsOwed.isEmpty)
    }

    @Test("A removal Health refuses stays owed and is made at the next catch-up")
    func refusedRemovalRetried() async throws {
        let deleted = try await fixture.seedFinished(100, 200)
        let health = FakeHealth(.on)
        try await inHealth(deleted, health)
        let session = await showingLog(health)
        health.refusesRemovals.withLock { $0 = true }
        await session.deleteWorkoutSession(deleted.id)
        await session.healthJobsLanded()
        #expect(session.log?.workoutSessions == [])
        #expect(health.inHealth.withLock { $0.contains(deleted.id) })
        health.refusesRemovals.withLock { $0 = false }
        await session.caughtUpHealth()
        #expect(health.inHealth.withLock { $0.isEmpty })
        #expect(session.health.removalsOwed.isEmpty)
    }

    @Test("Deleted with saving off, the workout leaves Log, and a relaunch with it on removes it")
    func offThenRelaunchRemoves() async throws {
        let deleted = try await fixture.seedFinished(100, 200)
        let health = FakeHealth(.on)
        try await inHealth(deleted, health)
        health.access.withLock { $0 = .off }
        let removalsBefore = health.removals.withLock { $0.count }
        let session = await showingLog(health)
        await session.deleteWorkoutSession(deleted.id)
        await session.healthJobsLanded()
        #expect(session.log?.workoutSessions == [])
        #expect(try await fixture.store().finishedWorkoutSessions().isEmpty)
        #expect(health.removals.withLock { $0.count } == removalsBefore)
        health.access.withLock { $0 = .on }
        await fixture.launched(health).caughtUpHealth()
        #expect(health.inHealth.withLock { $0.isEmpty })
        await fixture.launched(health).caughtUpHealth()
        #expect(health.removals.withLock { $0.count } == removalsBefore + 1)
    }

    @Test(
        "Never asked, or with no Health, a delete leaves Log and owes no removal, then or once on",
        arguments: [HealthAccess.notAsked, .unavailable],
    )
    func noHealthOwesNothing(access: HealthAccess) async throws {
        let deleted = try await fixture.seedFinished(100, 200)
        let health = FakeHealth(access)
        let session = await showingLog(health)
        // As at launch, the access is read before Log is shown.
        await session.caughtUpHealth()
        await session.deleteWorkoutSession(deleted.id)
        await session.healthJobsLanded()
        #expect(session.log?.workoutSessions == [])
        #expect(session.health.removalsOwed.isEmpty)
        #expect(fixture.defaults.object(forKey: HealthSaving.removalsKey) == nil)
        health.access.withLock { $0 = .on }
        await fixture.launched(health).caughtUpHealth()
        #expect(health.removals.withLock { $0.isEmpty })
    }

    @Test("A workout still owed to Health when deleted is never saved, saving turned on after")
    func deletedWhileOwedNeverSaved() async throws {
        let deleted = try await fixture.seedFinished(100, 200)
        let health = FakeHealth(.off)
        let session = await showingLog(health)
        await session.deleteWorkoutSession(deleted.id)
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
        await session.deleteWorkoutSession(deleted.id)
        health.release()
        await session.healthJobsLanded()
        #expect(health.attempts.withLock { $0 } == [first.id])
        #expect(health.inHealth.withLock { $0 } == [first.id])
    }

    @Test("A deleted workout leaves Health before the run's saves, one of which Health refuses")
    func removalBeforeFailingSave() async throws {
        let deleted = try await fixture.seedFinished(100, 200)
        let health = FakeHealth(.on)
        try await inHealth(deleted, health)
        let refused = try await fixture.seedFinished(300, 400)
        health.fails.withLock { $0 = [refused.id] }
        let session = await showingLog(health)
        health.holdsNext.withLock { $0 = true }
        await session.deleteWorkoutSession(deleted.id)
        await health.saveHeld()
        #expect(health.inHealth.withLock { !$0.contains(deleted.id) })
        health.release()
        await session.healthJobsLanded()
        #expect(health.attempts.withLock { $0.last } == refused.id)
        #expect(health.inHealth.withLock { $0.isEmpty })
        #expect(session.health.removalsOwed.isEmpty)
    }

    @Test("A workout deleted during its own save ends removed, and is never saved again")
    func deletedDuringItsSave() async throws {
        let deleted = try await fixture.seedFinished(100, 200)
        let health = FakeHealth(.on)
        let session = await showingLog(health)
        health.holdsNext.withLock { $0 = true }
        session.catchUpHealth()
        await health.saveHeld()
        await session.deleteWorkoutSession(deleted.id)
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
        let logged = try #require(session.workoutSession)
        await session.deleteWorkoutSession(logged.id)
        await session.healthJobsLanded()
        #expect(health.removals.withLock { $0.isEmpty })
        #expect(session.health.removalsOwed.isEmpty)
        session.finish(at: HealthFixture.at(70))
        await session.healthJobsLanded()
        #expect(health.inHealth.withLock { $0 } == [logged.id])
    }

    @Test("A workout deleted again while a relaunch's catch-up settles it still leaves Health")
    func deletedAgainDuringSettle() async throws {
        let deleted = try await fixture.seedFinished(100, 200)
        let health = FakeHealth(.on)
        try await inHealth(deleted, health)
        // The last launch was closed after the delete was sent, before it landed.
        HealthSaving(client: health.client, defaults: fixture.defaults).oweRemoval(of: deleted.id)
        let session = await showingLog(health)
        health.holdsNextRead.withLock { $0 = true }
        session.catchUpHealth()
        await health.readHeld()
        // Deleted again, its write landing only after this catch-up has read the store:
        // `deleteWorkoutSession` with its steps spread around the catch-up's settle.
        session.health.oweRemoval(of: deleted.id)
        health.releaseRead()
        await session.healthJobsLanded()
        session.workoutSessionWrites.yield(.delete(deleted.id))
        await session.caughtUpHealth()
        #expect(try await fixture.store().finishedWorkoutSessions().isEmpty)
        #expect(health.inHealth.withLock { $0.isEmpty })
        #expect(session.health.removalsOwed.isEmpty)
    }

    @Test("With saving off, a removal whose delete never landed is dropped, and it saves once on")
    func offSettles() async throws {
        let kept = try await fixture.seedFinished(100, 200)
        let health = FakeHealth(.off)
        HealthSaving(client: health.client, defaults: fixture.defaults).oweRemoval(of: kept.id)
        let session = fixture.launched(health)
        await session.caughtUpHealth()
        #expect(session.health.removalsOwed.isEmpty)
        #expect(fixture.defaults.object(forKey: HealthSaving.removalsKey) == nil)
        health.access.withLock { $0 = .on }
        await session.caughtUpHealth()
        #expect(health.inHealth.withLock { $0 } == [kept.id])
    }

    @Test("Removals owed outlive the session in the device's defaults, every one kept")
    func owedKeptOnDevice() {
        let client = FakeHealth(.off).client
        let saving = HealthSaving(client: client, defaults: fixture.defaults)
        let ids = (0 ..< 150).map { _ in UUID() }
        for id in ids {
            saving.oweRemoval(of: id)
        }
        saving.oweRemoval(of: ids[0])
        let relaunched = HealthSaving(client: client, defaults: fixture.defaults)
        #expect(relaunched.removalsOwed == ids)
        relaunched.forgetRemovals(of: Set(ids))
        #expect(fixture.defaults.object(forKey: HealthSaving.removalsKey) == nil)
    }

    private func workoutOfOne() throws -> Workout {
        let exercise = try #require(Exercise.builtIn(id: "barbell-bench-press"))
        return Workout(
            name: "Upper",
            exercises: [WorkoutExercise(exercise: exercise, weightUnit: .pounds)],
        )
    }
}
