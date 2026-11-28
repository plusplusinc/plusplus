import Foundation
import Health
import Testing
@testable import Session
@testable import WorkoutStore

/// Log's prompt to sync to Apple Health (`AppSession.healthPrompt`): made by a finish while
/// Health was never asked, kept on the device, gone for good after its ×, and the note that takes
/// its place for a moment after the × or a Don't Allow, kept in memory only.
@Suite("Apple Health prompt on Log")
struct HealthOfferTests {
    private let fixture: HealthFixture

    init() throws {
        fixture = try HealthFixture()
    }

    /// A session launched over the fixture's store and defaults, as at a relaunch, that has
    /// finished one workout starting at `start` seconds, its catch-up run.
    private func finished(
        _ health: FakeHealth,
        at start: Double = 10,
    ) async throws -> (session: AppSession, finished: WorkoutSession.ID) {
        let exercise = try #require(Exercise.builtIn(id: "barbell-bench-press"))
        let workout = Workout(
            name: "Upper",
            exercises: [WorkoutExercise(exercise: exercise, weightUnit: .pounds)],
        )
        let session = await launched(health, workout: workout)
        session.start(on: workout.id, at: HealthFixture.at(start))
        let logged = try #require(session.workoutSession)
        session.finish(at: HealthFixture.at(start + 60))
        await session.healthJobsLanded()
        return (session, logged.id)
    }

    /// A session launched over the fixture, its log and Health's access read, as the app's
    /// launch and Log read them.
    private func launched(_ health: FakeHealth, workout: Workout = Workout()) async -> AppSession {
        let session = fixture.launched(health, workout: workout)
        await session.refreshLog()
        session.health.refresh()
        return session
    }

    @Test("A finish with Health never asked shows the prompt, and a relaunch still shows it")
    func finishOffers() async throws {
        let health = FakeHealth(.notAsked, store: fixture.store())
        #expect(await launched(health).healthPrompt == nil)
        let (session, _) = try await finished(health)
        #expect(session.healthPrompt == .ask)
        #expect(health.asks.withLock { $0 } == 0)
        #expect(await launched(health).healthPrompt == .ask)
    }

    @Test("With Log's only workout deleted the prompt goes, and the next finish brings it back")
    func onlyWhileLogHoldsOne() async throws {
        let health = FakeHealth(.notAsked, store: fixture.store())
        let (session, first) = try await finished(health)
        await session.deleteWorkoutSession(first)
        #expect(session.healthPrompt == nil)
        let exercise = try #require(Exercise.builtIn(id: "barbell-bench-press"))
        let workout = Workout(exercises: [WorkoutExercise(exercise: exercise, weightUnit: .pounds)])
        let relaunched = await launched(health, workout: workout)
        #expect(relaunched.healthPrompt == nil)
        // From the finish itself, before any read of the log: Log's first frame after it.
        relaunched.start(on: workout.id, at: HealthFixture.at(200))
        relaunched.finish(at: HealthFixture.at(260))
        #expect(relaunched.healthPrompt == .ask)
    }

    @Test("The × shows its note at once and stores the dismissal; a relaunch shows nothing")
    func dismissIsForGood() async throws {
        let health = FakeHealth(.notAsked, store: fixture.store())
        let (session, _) = try await finished(health)
        session.health.declineOffer()
        #expect(session.healthPrompt == .note(.dismissed))
        // Stored with the tap, not at the note's end: a launch over the same defaults now,
        // as after the app is killed with the note up, finds it dismissed and no note.
        #expect(await launched(health).healthPrompt == nil)
        let (later, _) = try await finished(health, at: 100)
        #expect(later.healthPrompt == nil)
        #expect(later.health.access == .notAsked)
        #expect(health.asks.withLock { $0 } == 0)
    }

    @Test("The note's OK, or its fill run out, ends it, and the prompt doesn't come back")
    func endNote() async throws {
        let health = FakeHealth(.notAsked, store: fixture.store())
        let (session, _) = try await finished(health)
        session.health.declineOffer()
        session.health.endNote()
        #expect(session.healthPrompt == nil)
    }

    @Test("Don't Allow from the prompt shows the note that Apple Health can turn it on")
    func dontAllowFromThePrompt() async throws {
        let health = FakeHealth(.notAsked, store: fixture.store())
        health.answer.withLock { $0 = .off }
        let (session, _) = try await finished(health)
        await session.syncFromPrompt()
        #expect(session.healthPrompt == .note(.denied))
        session.health.endNote()
        #expect(session.healthPrompt == nil)
        #expect(await launched(health).healthPrompt == nil)
    }

    @Test("Allow from the prompt leaves nothing on Log and syncs the workout that brought it")
    func allowFromThePrompt() async throws {
        let health = FakeHealth(.notAsked, store: fixture.store())
        let (session, finished) = try await finished(health)
        #expect(health.saves.withLock { $0 }.isEmpty)
        await session.syncFromPrompt()
        await session.healthJobsLanded()
        #expect(session.healthPrompt == nil)
        #expect(health.asks.withLock { $0 } == 1)
        #expect(health.savedIDs == [finished])
    }

    @Test("Apple's sheet left unanswered leaves the prompt in place")
    func unansweredKeepsThePrompt() async throws {
        let health = FakeHealth(.notAsked, store: fixture.store())
        health.answer.withLock { $0 = .notAsked }
        let (session, _) = try await finished(health)
        await session.syncFromPrompt()
        #expect(health.asks.withLock { $0 } == 1)
        #expect(session.healthPrompt == .ask)
    }

    @Test("Don't Allow from Settings takes the prompt away and leaves no note on Log")
    func dontAllowFromSettings() async throws {
        let health = FakeHealth(.notAsked, store: fixture.store())
        health.answer.withLock { $0 = .off }
        let (session, _) = try await finished(health)
        await session.askToSaveToHealth()
        #expect(session.healthPrompt == nil)
    }

    @Test("A second ask while Apple's sheet is up, as from a double tap, asks nothing more")
    func oneAskAtATime() async {
        let health = FakeHealth(.notAsked, store: fixture.store())
        health.holdsNextAsk.withLock { $0 = true }
        let session = fixture.launched(health)
        let first = Task { await session.askToSaveToHealth() }
        await health.askHeld()
        await session.askToSaveToHealth()
        health.releaseAsk()
        await first.value
        #expect(health.asks.withLock { $0 } == 1)
        await session.askToSaveToHealth()
        #expect(health.asks.withLock { $0 } == 2)
    }

    @Test(
        "With Health asked before, or not on the device, a finish never shows the prompt",
        arguments: [HealthAccess.on, .off, .unavailable],
    )
    func answeredNeverOffers(access: HealthAccess) async throws {
        let health = FakeHealth(access, store: fixture.store())
        let (session, _) = try await finished(health)
        #expect(session.healthPrompt == nil)
    }
}
