import Foundation
import Health
import SwiftData
import Synchronization
@testable import Session
@testable import WorkoutStore

/// A Health whose access is set by the test, and which records each removal and save it takes.
/// As HealthKit does, it refuses a removal or save while the access isn't on.
final class FakeHealth: Sendable {
    struct SaveFailed: Error { }
    struct NotAllowed: Error { }

    let access: Mutex<HealthAccess>
    let accessReads = Mutex(0)
    let asks = Mutex(0)
    /// The logged workouts of each removal.
    let removals = Mutex<[[LoggedWorkout.ID]]>([])
    /// Each workout saved, with the finished logged workouts the store held as it was.
    let saves = Mutex<[(workout: HealthWorkout, stored: [LoggedWorkout.ID])]>([])
    /// Logged workouts whose next save throws.
    let failsOnce = Mutex<Set<LoggedWorkout.ID>>([])
    /// Whether saves hand back no id, as Health does with the phone locked.
    let returnsNoID = Mutex(false)
    /// Whether the next save waits for `release()`.
    let holdsNext = Mutex(false)
    private let held = Mutex<CheckedContinuation<Void, Never>?>(nil)
    private let heldSaves: AsyncStream<Void>
    private let heldSave: AsyncStream<Void>.Continuation
    private let store: Store?

    init(_ access: HealthAccess, store: Store? = nil) {
        self.access = Mutex(access)
        self.store = store
        (heldSaves, heldSave) = AsyncStream.makeStream()
    }

    var savedIDs: [LoggedWorkout.ID] {
        saves.withLock { $0.map(\.workout.id) }
    }

    /// Returns once a save is held.
    func saveHeld() async {
        var held = heldSaves.makeAsyncIterator()
        _ = await held.next()
    }

    func release() {
        held.withLock {
            $0?.resume()
            $0 = nil
        }
    }

    private nonisolated func takesHold() -> Bool {
        holdsNext.withLock { holds in
            defer { holds = false }
            return holds
        }
    }

    private nonisolated func allowed() throws {
        guard access.withLock({ $0 }) == .on else { throw NotAllowed() }
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
            remove: { ids in
                try self.allowed()
                self.removals.withLock { $0.append(ids) }
            },
            save: { workout in
                try self.allowed()
                if self.takesHold() {
                    await withCheckedContinuation { done in
                        self.held.withLock { $0 = done }
                        self.heldSave.yield()
                    }
                }
                if self.failsOnce.withLock({ $0.remove(workout.id) != nil }) {
                    throw SaveFailed()
                }
                let stored = try await self.store?.finishedLoggedWorkouts() ?? []
                self.saves.withLock { $0.append((workout, stored.map(\.id))) }
                return self.returnsNoID.withLock { $0 } ? nil : UUID()
            },
        )
    }
}

/// One in-memory store, whose sessions are launches of the app over it.
struct HealthFixture {
    let container: ModelContainer

    init() throws {
        container = try WorkoutStoreContainer.make(mode: .inMemory, schema: Store.schema)
    }

    static func at(_ seconds: Double) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    func store() -> Store {
        Store(modelContainer: container)
    }

    /// A session as launched over the store, showing `workout`; with `hasStore` false, as when
    /// the store didn't open.
    func launched(
        _ health: FakeHealth,
        workout: Workout = Workout(),
        exercises: ExerciseList = .builtIn,
        hasStore: Bool = true,
    ) -> AppSession {
        AppSession(
            workout: workout,
            exercises: exercises,
            store: hasStore ? store() : nil,
            namer: .muscleGroupsOnly,
            health: HealthSaving(client: health.client),
        )
    }

    /// A finished workout stored as Log holds it, from `start` to `end`.
    @discardableResult
    func seedFinished(
        _ start: Double,
        _ end: Double,
        pausedSeconds: Double = 0,
    ) async throws -> LoggedWorkout {
        let finished = LoggedWorkout(
            workoutID: UUID(),
            workoutName: "Upper",
            startedAt: Self.at(start),
            pausedSeconds: pausedSeconds,
        ).finishing(at: Self.at(end))
        try await store().save(finished)
        return finished
    }
}

extension AppSession {
    /// A catch-up, run to its end.
    func caughtUpHealth() async {
        catchUpHealth()
        await healthJobsLanded()
    }
}
