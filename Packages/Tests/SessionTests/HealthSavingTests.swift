import Foundation
import Health
import Observation
import Synchronization
import Testing
@testable import Session
@testable import WorkoutStore

/// A finish saving to Apple Health, through a fake client that answers as told.
@Suite("Apple Health saving")
struct HealthSavingTests {
    private let fixture: HealthFixture

    init() throws {
        fixture = try HealthFixture()
    }

    @Test("With saving on, a finish hands Health the workout after its write, and keeps its id")
    func finishSaves() async throws {
        let exercise = try #require(Exercise.builtIn(id: "barbell-bench-press"))
        let workout = Workout(
            name: "Upper",
            exercises: [WorkoutExercise(exercise: exercise, weightUnit: .pounds)],
        )
        let health = FakeHealth(.on, store: fixture.store())
        let session = fixture.launched(health, workout: workout)
        session.start(on: workout.id, at: HealthFixture.at(10))
        let logged = try #require(session.loggedWorkout)
        session.finish(at: HealthFixture.at(70))
        // Nothing reads Health in the Finish tap's turn, nor as the session was made.
        #expect(health.accessReads.withLock { $0 } == 0)
        await session.healthJobsLanded()
        let saves = health.saves.withLock { $0 }
        let saved = try #require(saves.first?.workout)
        #expect(saves.count == 1)
        #expect(saved.id == logged.id)
        #expect(saved.start == HealthFixture.at(10))
        #expect(saved.end == HealthFixture.at(70))
        #expect(saves.first?.stored == [logged.id])
        let read = try #require(try await fixture.store().finishedLoggedWorkouts().first)
        #expect(read.healthWorkoutID != nil)
    }

    @Test("A finish of created exercises, paused twice, hands Health their type and each pause")
    func finishCreatedPaused() async throws {
        let store = fixture.store()
        // Created exercises have no kind of their own, so they count as strength; with no
        // weight held, functional.
        let created = [
            CreatedExercise(name: "Couch stretch", muscleGroups: [.legs], measure: .time),
            CreatedExercise(name: "Doorway stretch", muscleGroups: [.chest], measure: .time),
        ]
        for exercise in created {
            try await store.save(exercise)
        }
        let rows = created.map {
            WorkoutExercise(exercise: Exercise(created: $0), weightUnit: .pounds)
        }
        let workout = Workout(name: "Stretch", exercises: rows)
        let health = FakeHealth(.on, store: store)
        let session = try await fixture.launched(
            health,
            workout: workout,
            exercises: store.exercises(),
        )
        session.start(on: workout.id, at: HealthFixture.at(10))
        for (row, seconds) in zip(rows, [20.0, 30]) {
            session.log(
                PlannedSet(row: row.id, round: 1, side: nil),
                of: row,
                at: HealthFixture.at(seconds),
            )
        }
        session.togglePause(at: HealthFixture.at(40))
        session.togglePause(at: HealthFixture.at(50))
        session.togglePause(at: HealthFixture.at(60))
        session.finish(at: HealthFixture.at(90))
        await session.healthJobsLanded()
        let saved = try #require(health.saves.withLock { $0.first?.workout })
        #expect(saved.activity == .functionalStrength)
        #expect(saved.pauses == [
            DateInterval(start: HealthFixture.at(40), end: HealthFixture.at(50)),
            DateInterval(start: HealthFixture.at(60), end: HealthFixture.at(90)),
        ])
        let stored = try #require(try await store.finishedLoggedWorkouts().first)
        #expect(stored.healthActivity == .functionalStrength)
        #expect(stored.pauses == saved.pauses)
    }

    @Test("A finish with no store behind the session, its write never landing, sends nothing")
    func noStoreSendsNothing() async throws {
        let exercise = try #require(Exercise.builtIn(id: "barbell-bench-press"))
        let workout = Workout(exercises: [WorkoutExercise(exercise: exercise, weightUnit: .pounds)])
        let health = FakeHealth(.on)
        let session = fixture.launched(health, workout: workout, hasStore: false)
        session.start(on: workout.id, at: HealthFixture.at(10))
        session.finish(at: HealthFixture.at(70))
        await session.healthJobsLanded()
        #expect(health.savedIDs.isEmpty)
    }

    @Test("Access is read at the first refresh, not as saving is made, and follows each after")
    func accessFollowsClient() async {
        let health = FakeHealth(.notAsked)
        let saving = HealthSaving(client: health.client)
        #expect(saving.access == nil)
        saving.refresh()
        #expect(saving.access == .notAsked)
        health.access.withLock { $0 = .off }
        await saving.refreshed()
        #expect(saving.access == .off)
        health.access.withLock { $0 = .notAsked }
        await saving.ask()
        #expect(health.asks.withLock { $0 } == 1)
        #expect(saving.access == .on)
    }

    @Test("A read that finds the same answer tells no view the access changed, as a catch-up's")
    func sameAnswerUnchanged() async {
        let health = FakeHealth(.notAsked)
        let saving = HealthSaving(client: health.client)
        saving.refresh()
        let changes = Mutex(0)
        withObservationTracking {
            _ = saving.access
        } onChange: {
            changes.withLock { $0 += 1 }
        }
        saving.refresh()
        await saving.refreshed()
        #expect(changes.withLock { $0 } == 0)
        health.access.withLock { $0 = .on }
        await saving.refreshed()
        #expect(changes.withLock { $0 } == 1)
    }

    @Test("A slow read that began before the person allowed saving doesn't show it off after")
    func overtakenReadDropped() async {
        let health = FakeHealth(.off)
        let saving = HealthSaving(client: health.client)
        health.holdsNextRead.withLock { $0 = true }
        let slow = Task { await saving.refreshed() }
        await health.readHeld()
        await saving.ask()
        #expect(saving.access == .on)
        health.releaseRead()
        await slow.value
        #expect(saving.access == .on)
        #expect(health.accessReads.withLock { $0 } == 2)
    }
}
