import Foundation
import SwiftData
import Testing
@testable import Session
@testable import WorkoutStore

/// Deleting a finished logged workout from Log through the session: it leaves the log and the
/// store, after any write of it still queued, never the one in progress (the store refuses it,
/// `StoreDeleteTests`), and a delete the store
/// refuses leaves it in the log. A relaunch is a second store over the same container.
@Suite("Workout session Log delete")
struct AppSessionLogDeleteTests {
    private let container: ModelContainer
    private let workout: Workout

    init() async throws {
        container = try WorkoutStoreContainer.make(mode: .inMemory, schema: Store.schema)
        let exercise = try #require(Exercise.builtIn(id: "barbell-bench-press"))
        workout = Workout(
            name: "Upper",
            exercises: [WorkoutExercise(exercise: exercise, weightUnit: .pounds)],
        )
        try await relaunch().save(workout, at: Self.at(1))
    }

    private func relaunch() -> Store {
        Store(modelContainer: container)
    }

    private static func at(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    private func finished(at seconds: TimeInterval) -> WorkoutSession {
        WorkoutSession(
            workoutID: workout.id,
            workoutName: workout.name,
            startedAt: Self.at(seconds),
        )
        .finishing(at: Self.at(seconds + 60))
    }

    @Test("A finished workout deleted from Log leaves the log, then the store at a relaunch")
    func deleteFinished() async throws {
        let deleted = finished(at: 10)
        let kept = finished(at: 100)
        try await relaunch().save(deleted)
        try await relaunch().save(kept)
        let session = AppSession(workout: workout, store: relaunch(), namer: .muscleGroupsOnly)
        await session.refreshLog()
        await session.deleteWorkoutSession(deleted.id)
        #expect(session.log?.workoutSessions == [kept])
        #expect(try await relaunch().finishedWorkoutSessions() == [kept])
    }

    @Test("A delete sent as the workout's Finish is still landing deletes it once it lands")
    func deleteBehindFinish() async throws {
        let session = AppSession(workout: workout, store: relaunch(), namer: .muscleGroupsOnly)
        session.start(on: workout.id, at: Self.at(10))
        let workoutSession = try #require(session.workoutSession)
        session.finish(at: Self.at(20))
        await session.deleteWorkoutSession(workoutSession.id)
        #expect(session.log?.workoutSessions == [])
        let stored = try ModelContext(container).fetch(FetchDescriptor<StoredWorkoutSession>())
        #expect(stored.isEmpty)
    }

    @Test("Delete is refused for the workout in progress, which stays in the store")
    func inProgressRefused() async throws {
        let session = AppSession(workout: workout, store: relaunch(), namer: .muscleGroupsOnly)
        session.start(on: workout.id, at: Self.at(10))
        let workoutSession = try #require(session.workoutSession)
        await session.deleteWorkoutSession(workoutSession.id)
        await session.writesLanded()
        #expect(session.workoutSession == workoutSession)
        let launch = try await relaunch().launch(weightUnit: .pounds)
        #expect(launch.workoutSession == workoutSession)
    }

    @Test("A delete the store refuses leaves the workout in the log")
    func failedDeleteListed() async throws {
        // A folder of its own, so its removal takes SQLite's files beside the store too.
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "PlusPlus.store")
        let workoutSession = finished(at: 10)
        try await Store(modelContainer: ModelContainer(
            for: Store.schema,
            configurations: ModelConfiguration(schema: Store.schema, url: url),
        )).save(workoutSession)
        // The same file opened read-only: its reads work, and its saves throw.
        let readOnly = try ModelContainer(
            for: Store.schema,
            configurations: ModelConfiguration(schema: Store.schema, url: url, allowsSave: false),
        )
        await #expect(throws: (any Error).self) {
            try await Store(modelContainer: readOnly).deleteWorkoutSession(workoutSession.id)
        }
        let session = AppSession(
            workout: workout,
            store: Store(modelContainer: readOnly),
            namer: .muscleGroupsOnly,
        )
        await session.deleteWorkoutSession(workoutSession.id)
        #expect(session.log?.workoutSessions == [workoutSession])
    }
}
