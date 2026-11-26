import Foundation
import Health
import Testing
@testable import Session
@testable import WorkoutStore

/// Apple Health's catch-up: what the store holds with no Health id goes, each once. A relaunch
/// is a second session over the same store.
@Suite("Apple Health catch-up")
struct HealthCatchUpTests {
    private let fixture: HealthFixture

    init() throws {
        fixture = try HealthFixture()
    }

    @Test("Three in Log, saving allowed: one removal, each saved once with its dates, never again")
    func allowSendsAll() async throws {
        let first = try await fixture.seedFinished(100, 200)
        let third = try await fixture.seedFinished(500, 600)
        let second = try await fixture.seedFinished(300, 400)
        let health = FakeHealth(.notAsked)
        let session = fixture.launched(health)
        await session.caughtUpHealth()
        #expect(health.savedIDs.isEmpty)
        await session.askToSaveToHealth()
        await session.healthJobsLanded()
        let saved = health.saves.withLock { $0.map(\.workout) }
        #expect(saved.map(\.id) == [first.id, second.id, third.id])
        #expect(saved.map(\.start) == [100, 300, 500].map(HealthFixture.at))
        #expect(saved.map(\.end) == [200, 400, 600].map(HealthFixture.at))
        await session.askToSaveToHealth()
        await session.caughtUpHealth()
        await fixture.launched(health).caughtUpHealth()
        await fixture.launched(health).caughtUpHealth()
        #expect(health.savedIDs == [first.id, second.id, third.id])
        #expect(health.removals.withLock { $0 } == [[first.id, second.id, third.id]])
    }

    @Test("With saving off a catch-up only reads access; turned on, the next saves it once")
    func offThenOn() async throws {
        let finished = try await fixture.seedFinished(10, 70)
        let health = FakeHealth(.off)
        let session = fixture.launched(health)
        await session.caughtUpHealth()
        #expect(health.savedIDs.isEmpty)
        #expect(health.removals.withLock { $0 }.isEmpty)
        #expect(health.accessReads.withLock { $0 } == 1)
        health.access.withLock { $0 = .on }
        await session.caughtUpHealth()
        await session.caughtUpHealth()
        #expect(health.savedIDs == [finished.id])
    }

    @Test("A workout Health keeps refusing, access on, holds back none after it, and stays owed")
    func refusedSaveSkipped() async throws {
        let refused = try await fixture.seedFinished(100, 200)
        let second = try await fixture.seedFinished(300, 400)
        let third = try await fixture.seedFinished(500, 600)
        let health = FakeHealth(.on)
        health.fails.withLock { $0 = [refused.id] }
        let session = fixture.launched(health)
        await session.caughtUpHealth()
        #expect(health.savedIDs == [second.id, third.id])
        #expect(try await fixture.store().owedToHealth().map(\.id) == [refused.id])
        await session.caughtUpHealth()
        health.fails.withLock { $0 = [] }
        await session.caughtUpHealth()
        #expect(health.attempts.withLock { $0 } == [
            refused.id, second.id, third.id, refused.id, refused.id,
        ])
        #expect(health.savedIDs == [second.id, third.id, refused.id])
        #expect(health.removals.withLock { $0 } == [
            [refused.id, second.id, third.id], [refused.id], [refused.id],
        ])
        #expect(try await fixture.store().owedToHealth().isEmpty)
    }

    @Test("A save Health hands back no id for stays owed, removed and saved again in its place")
    func noIDSavedAgain() async throws {
        let finished = try await fixture.seedFinished(10, 70)
        let health = FakeHealth(.on)
        health.returnsNoID.withLock { $0 = true }
        let session = fixture.launched(health)
        await session.caughtUpHealth()
        #expect(try await fixture.store().owedToHealth().map(\.id) == [finished.id])
        health.returnsNoID.withLock { $0 = false }
        await session.caughtUpHealth()
        await session.caughtUpHealth()
        #expect(health.savedIDs == [finished.id, finished.id])
        #expect(health.removals.withLock { $0 } == [[finished.id], [finished.id]])
        #expect(try await fixture.store().owedToHealth().isEmpty)
    }

    @Test("Catch-ups asked during one run queue one more, which saves nothing twice")
    func overlappingCatchUps() async throws {
        let first = try await fixture.seedFinished(100, 200)
        let second = try await fixture.seedFinished(300, 400)
        let health = FakeHealth(.on)
        health.holdsNext.withLock { $0 = true }
        let session = fixture.launched(health)
        session.catchUpHealth()
        await health.saveHeld()
        session.catchUpHealth()
        session.catchUpHealth()
        session.catchUpHealth()
        health.release()
        await session.healthJobsLanded()
        #expect(health.savedIDs == [first.id, second.id])
        // The run held, then the one the three asks queued.
        #expect(health.accessReads.withLock { $0 } == 2)
    }

    @Test("Saving turned off mid-catch-up saves nothing more, and Settings reads it off")
    func offMidCatchUp() async throws {
        let first = try await fixture.seedFinished(100, 200)
        try await fixture.seedFinished(300, 400)
        try await fixture.seedFinished(500, 600)
        let health = FakeHealth(.on)
        health.holdsNext.withLock { $0 = true }
        let session = fixture.launched(health)
        session.catchUpHealth()
        await health.saveHeld()
        health.access.withLock { $0 = .off }
        health.release()
        await session.healthJobsLanded()
        #expect(health.savedIDs == [first.id])
        #expect(session.health.access == .off)
        // Once at the start, once after the second save threw.
        #expect(health.accessReads.withLock { $0 } == 2)
    }
}
