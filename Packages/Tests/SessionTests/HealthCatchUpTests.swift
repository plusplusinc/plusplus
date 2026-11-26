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

    private static func at(_ seconds: Double) -> Date {
        HealthFixture.at(seconds)
    }

    @Test("A finish whose save never happened is saved by the next launch's catch-up, once")
    func launchCatchesUp() async throws {
        let finished = try await fixture.seedFinished(10, 70)
        let health = FakeHealth(.on)
        await fixture.launched(health).caughtUpHealth()
        #expect(health.savedIDs == [finished.id])
        await fixture.launched(health).caughtUpHealth()
        #expect(health.savedIDs == [finished.id])
    }

    @Test("Three in Log, saving allowed: each saved once with its own dates, and never again")
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
        #expect(saved.map(\.start) == [100, 300, 500].map(Self.at))
        #expect(saved.map(\.end) == [200, 400, 600].map(Self.at))
        await session.askToSaveToHealth()
        await session.caughtUpHealth()
        await fixture.launched(health).caughtUpHealth()
        await fixture.launched(health).caughtUpHealth()
        #expect(health.savedIDs == [first.id, second.id, third.id])
    }

    @Test("A catch-up saves only what Health can have, and goes on past what it can't")
    func withheldSkipped() async throws {
        try await fixture.seedFinished(100, 200, pausedSeconds: 30)
        let sendable = try await fixture.seedFinished(300, 400)
        try await fixture.seedFinished(500, 500)
        let health = FakeHealth(.on)
        await fixture.launched(health).caughtUpHealth()
        #expect(health.savedIDs == [sendable.id])
    }

    @Test("With saving off a catch-up saves nothing; turned on, the next saves it once")
    func offThenOn() async throws {
        let finished = try await fixture.seedFinished(10, 70)
        let health = FakeHealth(.off)
        let session = fixture.launched(health)
        await session.caughtUpHealth()
        #expect(health.savedIDs.isEmpty)
        #expect(health.accessReads.withLock { $0 } == 1)
        health.access.withLock { $0 = .on }
        await session.caughtUpHealth()
        await session.caughtUpHealth()
        #expect(health.savedIDs == [finished.id])
    }

    @Test("A save that fails leaves the others saved, and is saved at the next catch-up")
    func failedSaveRetried() async throws {
        let first = try await fixture.seedFinished(100, 200)
        let failing = try await fixture.seedFinished(300, 400)
        let third = try await fixture.seedFinished(500, 600)
        let health = FakeHealth(.on)
        health.failsOnce.withLock { $0 = [failing.id] }
        let session = fixture.launched(health)
        await session.caughtUpHealth()
        #expect(health.savedIDs == [first.id, third.id])
        await session.caughtUpHealth()
        #expect(health.savedIDs == [first.id, third.id, failing.id])
    }

    @Test("A save Health hands back no id for stays owed, and is saved again in its place")
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
        #expect(try await fixture.store().owedToHealth().isEmpty)
    }

    @Test("Two catch-ups asked during one save run one after the other, each workout saved once")
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
        health.release()
        await session.healthJobsLanded()
        #expect(health.savedIDs == [first.id, second.id])
    }

    @Test("Saving turned off mid-catch-up saves nothing more")
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
    }

    @Test("A workout deleted from Log while a catch-up saves another is not saved")
    func deletedMidCatchUp() async throws {
        let first = try await fixture.seedFinished(100, 200)
        let deleted = try await fixture.seedFinished(300, 400)
        let third = try await fixture.seedFinished(500, 600)
        let health = FakeHealth(.on)
        health.holdsNext.withLock { $0 = true }
        let session = fixture.launched(health)
        session.catchUpHealth()
        await health.saveHeld()
        await session.deleteLoggedWorkout(deleted.id)
        health.release()
        await session.healthJobsLanded()
        await session.caughtUpHealth()
        #expect(health.savedIDs == [first.id, third.id])
    }
}
