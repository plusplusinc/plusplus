import Foundation
import Health
import Testing
@testable import Session
@testable import WorkoutStore

/// The one-time card on Log that asks to save to Apple Health: made by a finish while Health
/// was never asked, kept on the device, gone for good after "Not now" or Apple's sheet.
@Suite("Apple Health offer on Log")
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
    ) async throws -> (session: AppSession, finished: LoggedWorkout.ID) {
        let exercise = try #require(Exercise.builtIn(id: "barbell-bench-press"))
        let workout = Workout(
            name: "Upper",
            exercises: [WorkoutExercise(exercise: exercise, weightUnit: .pounds)],
        )
        let session = await launched(health, workout: workout)
        session.start(on: workout.id, at: HealthFixture.at(start))
        let logged = try #require(session.loggedWorkout)
        session.finish(at: HealthFixture.at(start + 60))
        await session.healthJobsLanded()
        return (session, logged.id)
    }

    /// A session launched over the fixture, its log read, as the app's launch reads it.
    private func launched(_ health: FakeHealth, workout: Workout = Workout()) async -> AppSession {
        let session = fixture.launched(health, workout: workout)
        await session.refreshLog()
        return session
    }

    @Test("A finish with Health never asked shows the card, and a relaunch still shows it")
    func finishOffers() async throws {
        let health = FakeHealth(.notAsked, store: fixture.store())
        #expect(await !launched(health).showsHealthOffer)
        let (session, _) = try await finished(health)
        #expect(session.showsHealthOffer)
        #expect(health.asks.withLock { $0 } == 0)
        let relaunched = await launched(health)
        relaunched.health.refresh()
        #expect(relaunched.showsHealthOffer)
    }

    @Test("With Log's only workout deleted the card goes, and the next finish brings it back")
    func onlyWhileLogHoldsOne() async throws {
        let health = FakeHealth(.notAsked, store: fixture.store())
        let (session, first) = try await finished(health)
        await session.deleteLoggedWorkout(first)
        #expect(!session.showsHealthOffer)
        let exercise = try #require(Exercise.builtIn(id: "barbell-bench-press"))
        let workout = Workout(exercises: [WorkoutExercise(exercise: exercise, weightUnit: .pounds)])
        let relaunched = await launched(health, workout: workout)
        relaunched.health.refresh()
        #expect(!relaunched.showsHealthOffer)
        // From the finish itself, before any read of the log: Log's first frame after it.
        relaunched.start(on: workout.id, at: HealthFixture.at(200))
        relaunched.finish(at: HealthFixture.at(260))
        #expect(relaunched.showsHealthOffer)
    }

    @Test("Not now hides the card for good: after a later finish and a relaunch, never asking")
    func notNowIsForGood() async throws {
        let health = FakeHealth(.notAsked, store: fixture.store())
        let (session, _) = try await finished(health)
        session.health.declineOffer()
        #expect(!session.showsHealthOffer)
        let (later, _) = try await finished(health, at: 100)
        #expect(!later.showsHealthOffer)
        #expect(later.health.access == .notAsked)
        #expect(health.asks.withLock { $0 } == 0)
    }

    @Test(
        "Answered from the card, the card is gone, and Allow saves the workout that brought it",
        arguments: [HealthAccess.on, .off],
    )
    func answerFromTheCard(answer: HealthAccess) async throws {
        let health = FakeHealth(.notAsked, store: fixture.store())
        health.answer.withLock { $0 = answer }
        let (session, finished) = try await finished(health)
        #expect(health.saves.withLock { $0 }.isEmpty)
        await session.askToSaveToHealth()
        await session.healthJobsLanded()
        #expect(health.asks.withLock { $0 } == 1)
        let saved = health.saves.withLock { $0.map(\.workout.id) }
        #expect(saved == (answer == .on ? [finished] : []))
        #expect(!session.showsHealthOffer)
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
        "With Health asked before, or not on the device, a finish never shows the card",
        arguments: [HealthAccess.on, .off, .unavailable],
    )
    func answeredNeverOffers(access: HealthAccess) async throws {
        let health = FakeHealth(access, store: fixture.store())
        let (session, _) = try await finished(health)
        #expect(!session.showsHealthOffer)
    }
}
