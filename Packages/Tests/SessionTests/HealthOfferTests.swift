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
        let session = fixture.launched(health, workout: workout)
        session.start(on: workout.id, at: HealthFixture.at(start))
        let logged = try #require(session.loggedWorkout)
        session.finish(at: HealthFixture.at(start + 60))
        await session.healthJobsLanded()
        return (session, logged.id)
    }

    @Test("A finish with Health never asked shows the card, and a relaunch still shows it")
    func finishOffers() async throws {
        let health = FakeHealth(.notAsked, store: fixture.store())
        #expect(!fixture.launched(health).health.showsOffer)
        let (session, _) = try await finished(health)
        #expect(session.health.showsOffer)
        #expect(health.asks.withLock { $0 } == 0)
        let relaunched = HealthSaving(client: health.client, defaults: fixture.defaults)
        relaunched.refresh()
        #expect(relaunched.showsOffer)
    }

    @Test("Not now hides the card for good: after a later finish and a relaunch, never asking")
    func notNowIsForGood() async throws {
        let health = FakeHealth(.notAsked, store: fixture.store())
        let (session, _) = try await finished(health)
        session.health.declineOffer()
        #expect(!session.health.showsOffer)
        let (later, _) = try await finished(health, at: 100)
        #expect(!later.health.showsOffer)
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
        #expect(!session.health.showsOffer)
    }

    @Test(
        "With Health asked before, or not on the device, a finish never shows the card",
        arguments: [HealthAccess.on, .off, .unavailable],
    )
    func answeredNeverOffers(access: HealthAccess) async throws {
        let health = FakeHealth(access, store: fixture.store())
        let (session, _) = try await finished(health)
        #expect(!session.health.showsOffer)
    }
}
