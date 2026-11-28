import Foundation
import Health
import SwiftData
import Synchronization
import Testing
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
    /// What Apple's sheet is answered with at an ask: Allow, unless set.
    let answer = Mutex(HealthAccess.on)
    /// Whether the next ask waits, Apple's sheet up, for `releaseAsk()`.
    let holdsNextAsk = Mutex(false)
    private let heldAskDone = Mutex<CheckedContinuation<Void, Never>?>(nil)
    private let heldAsks: AsyncStream<Void>
    private let heldAsk: AsyncStream<Void>.Continuation
    /// The logged workouts of each removal.
    let removals = Mutex<[[WorkoutSession.ID]]>([])
    /// The logged workouts Health holds a workout tagged for, as saves and removals leave them.
    let inHealth = Mutex<Set<WorkoutSession.ID>>([])
    /// Whether removals throw, with access on.
    let refusesRemovals = Mutex(false)
    /// Each workout saved, with the finished logged workouts the store held as it was.
    let saves = Mutex<[(workout: HealthWorkout, stored: [WorkoutSession.ID])]>([])
    /// Each logged workout a save was tried for, saved or not.
    let attempts = Mutex<[WorkoutSession.ID]>([])
    /// Logged workouts whose saves throw, with access on, for as long as they are here.
    let fails = Mutex<Set<WorkoutSession.ID>>([])
    /// Whether the next access read, having read the access, waits for `releaseRead()`.
    let holdsNextRead = Mutex(false)
    private let readGate = DispatchSemaphore(value: 0)
    private let heldReads: AsyncStream<Void>
    private let heldRead: AsyncStream<Void>.Continuation
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
        (heldReads, heldRead) = AsyncStream.makeStream()
        (heldAsks, heldAsk) = AsyncStream.makeStream()
    }

    /// Returns once an ask is held.
    func askHeld() async {
        var held = heldAsks.makeAsyncIterator()
        _ = await held.next()
    }

    /// Answers the held ask with `answer`.
    func releaseAsk() {
        heldAskDone.withLock {
            $0?.resume()
            $0 = nil
        }
    }

    /// Returns once an access read is held.
    func readHeld() async {
        var held = heldReads.makeAsyncIterator()
        _ = await held.next()
    }

    /// Lets the held read return what it read.
    func releaseRead() {
        readGate.signal()
    }

    var savedIDs: [WorkoutSession.ID] {
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
                let access = self.access.withLock { $0 }
                let holds = self.holdsNextRead.withLock { holds in
                    defer { holds = false }
                    return holds
                }
                if holds {
                    // `access` is synchronous, as HealthKit's is, so the held read blocks its
                    // thread, which is off the main actor (`HealthSaving.refreshed()`).
                    self.heldRead.yield()
                    self.readGate.wait()
                }
                return access
            },
            ask: {
                self.asks.withLock { $0 += 1 }
                if self.holdsNextAsk.withLock({ holds in
                    defer { holds = false }
                    return holds
                }) {
                    await withCheckedContinuation { done in
                        self.heldAskDone.withLock { $0 = done }
                        self.heldAsk.yield()
                    }
                }
                let answer = self.answer.withLock { $0 }
                self.access.withLock { $0 = answer }
            },
            remove: { ids in
                try self.allowed()
                if self.refusesRemovals.withLock({ $0 }) {
                    throw SaveFailed()
                }
                self.removals.withLock { $0.append(ids) }
                self.inHealth.withLock { $0.subtract(ids) }
            },
            save: { workout in
                try self.allowed()
                self.attempts.withLock { $0.append(workout.id) }
                if self.takesHold() {
                    await withCheckedContinuation { done in
                        self.held.withLock { $0 = done }
                        self.heldSave.yield()
                    }
                }
                if self.fails.withLock({ $0.contains(workout.id) }) {
                    throw SaveFailed()
                }
                let stored = try await self.store?.finishedWorkoutSessions() ?? []
                self.saves.withLock { $0.append((workout, stored.map(\.id))) }
                self.inHealth.withLock { _ = $0.insert(workout.id) }
                return self.returnsNoID.withLock { $0 } ? nil : UUID()
            },
        )
    }
}

/// One in-memory store and one device's defaults, whose sessions are launches of the app over
/// them.
struct HealthFixture {
    let container: ModelContainer
    let defaults: UserDefaults
    private let device: DeviceDefaults

    init() throws {
        container = try WorkoutStoreContainer.make(mode: .inMemory, schema: Store.schema)
        device = DeviceDefaults()
        defaults = try #require(UserDefaults(suiteName: device.name))
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
            health: HealthSaving(client: health.client, defaults: defaults),
        )
    }

    /// A finished workout stored as Log holds it, from `start` to `end`.
    @discardableResult
    func seedFinished(
        _ start: Double,
        _ end: Double,
        pausedSeconds: Double = 0,
    ) async throws -> WorkoutSession {
        let finished = WorkoutSession(
            workoutID: UUID(),
            workoutName: "Upper",
            startedAt: Self.at(start),
            pausedSeconds: pausedSeconds,
        ).finishing(at: Self.at(end))
        try await store().save(finished)
        return finished
    }
}

/// A defaults domain of the test's own, on disk as a device's is, removed once the test is done.
private final class DeviceDefaults: Sendable {
    let name = "HealthFixture.\(UUID().uuidString)"

    deinit {
        UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
    }
}

extension AppSession {
    /// A catch-up, run to its end.
    func caughtUpHealth() async {
        catchUpHealth()
        await healthJobsLanded()
    }
}
