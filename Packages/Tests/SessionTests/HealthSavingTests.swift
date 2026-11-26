import Foundation
import Health
import SwiftData
import Synchronization
import Testing
@testable import Session
@testable import WorkoutStore

/// Saving to Apple Health through a fake client that answers as told and records each save.
@Suite("Apple Health saving")
struct HealthSavingTests {
    /// A Health whose access is set by the test, and whose saves arrive on `saved`.
    private final class FakeHealth: Sendable {
        let access: Mutex<HealthAccess>
        let accessReads = Mutex(0)
        let asks = Mutex(0)
        let saveCount = Mutex(0)
        /// Each workout saved, with the finished logged workouts the store held as it was.
        let saved: AsyncStream<(HealthWorkout, [LoggedWorkout.ID])>
        private let saves: AsyncStream<(HealthWorkout, [LoggedWorkout.ID])>.Continuation
        private let store: Store?

        init(_ access: HealthAccess, store: Store? = nil) {
            self.access = Mutex(access)
            self.store = store
            (saved, saves) = AsyncStream.makeStream()
        }

        var client: HealthClient {
            HealthClient(
                access: {
                    self.accessReads.withLock { $0 += 1 }
                    return self.access.withLock { $0 }
                },
                ask: {
                    self.asks.withLock { $0 += 1 }
                    self.access.withLock { $0 = .on }
                },
                save: { workout in
                    self.saveCount.withLock { $0 += 1 }
                    let stored = try await self.store?.finishedLoggedWorkouts() ?? []
                    self.saves.yield((workout, stored.map(\.id)))
                },
            )
        }
    }

    private static func at(_ seconds: Double) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    @Test("With saving on, a finish hands Health the workout after its write, reading access then")
    func finishSaves() async throws {
        let container = try WorkoutStoreContainer.make(mode: .inMemory, schema: Store.schema)
        let exercise = try #require(Exercise.builtIn(id: "barbell-bench-press"))
        let workout = Workout(
            name: "Upper",
            exercises: [WorkoutExercise(exercise: exercise, weightUnit: .pounds)],
        )
        let health = FakeHealth(.on, store: Store(modelContainer: container))
        let session = AppSession(
            workout: workout,
            store: Store(modelContainer: container),
            namer: .muscleGroupsOnly,
            health: HealthSaving(client: health.client),
        )
        session.start(on: workout.id, at: Self.at(10))
        let logged = try #require(session.loggedWorkout)
        session.finish(at: Self.at(70))
        // Nothing reads Health in the Finish tap's turn, nor as the session was made.
        #expect(health.accessReads.withLock { $0 } == 0)
        var saves = health.saved.makeAsyncIterator()
        let (saved, storedAtSave) = try #require(await saves.next())
        #expect(saved.id == logged.id)
        #expect(saved.start == Self.at(10))
        #expect(saved.end == Self.at(70))
        #expect(storedAtSave == [logged.id])
        #expect(health.saveCount.withLock { $0 } == 1)
    }

    @Test("With saving off, a save asks Health for nothing")
    func offSavesNothing() async {
        let health = FakeHealth(.off)
        let saving = HealthSaving(client: health.client)
        let finished = LoggedWorkout(workoutID: UUID(), workoutName: "Upper", startedAt: Self.at(0))
            .finishing(at: Self.at(60))
        await saving.save(Result { () throws(HealthWorkout.Withheld) in
            try HealthWorkout(finished: finished, resumedSeconds: 0, pausedSince: nil)
        })
        #expect(health.saveCount.withLock { $0 } == 0)
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
