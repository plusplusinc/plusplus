import Foundation
import Health
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

    private static func at(_ seconds: Double) -> Date {
        HealthFixture.at(seconds)
    }

    @Test("With saving on, a finish hands Health the workout after its write, and keeps its id")
    func finishSaves() async throws {
        let exercise = try #require(Exercise.builtIn(id: "barbell-bench-press"))
        let workout = Workout(
            name: "Upper",
            exercises: [WorkoutExercise(exercise: exercise, weightUnit: .pounds)],
        )
        let health = FakeHealth(.on, store: fixture.store())
        let session = AppSession(
            workout: workout,
            store: fixture.store(),
            namer: .muscleGroupsOnly,
            health: HealthSaving(client: health.client),
        )
        session.start(on: workout.id, at: Self.at(10))
        let logged = try #require(session.loggedWorkout)
        session.finish(at: Self.at(70))
        // Nothing reads Health in the Finish tap's turn, nor as the session was made.
        #expect(health.accessReads.withLock { $0 } == 0)
        await session.healthJobsLanded()
        let saves = health.saves.withLock { $0 }
        let saved = try #require(saves.first?.workout)
        #expect(saves.count == 1)
        #expect(saved.id == logged.id)
        #expect(saved.start == Self.at(10))
        #expect(saved.end == Self.at(70))
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
        let session = try await AppSession(
            workout: workout,
            exercises: store.exercises(),
            store: store,
            namer: .muscleGroupsOnly,
            health: HealthSaving(client: health.client),
        )
        session.start(on: workout.id, at: Self.at(10))
        for (row, seconds) in zip(rows, [20.0, 30]) {
            session.log(PlannedSet(row: row.id, round: 1), of: row, at: Self.at(seconds))
        }
        session.togglePause(at: Self.at(40))
        session.togglePause(at: Self.at(50))
        session.togglePause(at: Self.at(60))
        session.finish(at: Self.at(90))
        await session.healthJobsLanded()
        let saved = try #require(health.saves.withLock { $0.first?.workout })
        #expect(saved.activity == .functionalStrength)
        #expect(saved.pauses == [
            DateInterval(start: Self.at(40), end: Self.at(50)),
            DateInterval(start: Self.at(60), end: Self.at(90)),
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
        let session = AppSession(
            workout: workout,
            store: nil,
            namer: .muscleGroupsOnly,
            health: HealthSaving(client: health.client),
        )
        session.start(on: workout.id, at: Self.at(10))
        session.finish(at: Self.at(70))
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
        saving.refresh()
        #expect(saving.access == .off)
        health.access.withLock { $0 = .notAsked }
        await saving.ask()
        #expect(health.asks.withLock { $0 } == 1)
        #expect(saving.access == .on)
    }
}
