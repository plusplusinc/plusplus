import Foundation
import SwiftData
import Testing
@testable import Session
@testable import WorkoutStore

/// Deleting a finished logged workout from Log through the session: it leaves the log and the
/// store, after any write of it still queued, never the one in progress, and a delete the store
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

    private func finished(at seconds: TimeInterval) -> LoggedWorkout {
        LoggedWorkout(workoutID: workout.id, workoutName: workout.name, startedAt: Self.at(seconds))
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
        await session.deleteLoggedWorkout(deleted.id)
        #expect(session.log?.loggedWorkouts == [kept])
        #expect(try await relaunch().finishedLoggedWorkouts() == [kept])
    }

    @Test("A delete sent as the workout's Finish is still landing deletes it once it lands")
    func deleteBehindFinish() async throws {
        let session = AppSession(workout: workout, store: relaunch(), namer: .muscleGroupsOnly)
        session.start(on: workout.id, at: Self.at(10))
        let loggedWorkout = try #require(session.loggedWorkout)
        session.finish(at: Self.at(20))
        await session.deleteLoggedWorkout(loggedWorkout.id)
        #expect(session.log?.loggedWorkouts == [])
        let stored = try ModelContext(container).fetch(FetchDescriptor<StoredWorkout>())
        #expect(stored.isEmpty)
    }

    @Test("Delete is refused for the workout in progress, which stays in the store")
    func inProgressRefused() async throws {
        let session = AppSession(workout: workout, store: relaunch(), namer: .muscleGroupsOnly)
        session.start(on: workout.id, at: Self.at(10))
        let loggedWorkout = try #require(session.loggedWorkout)
        await session.deleteLoggedWorkout(loggedWorkout.id)
        await session.writesLanded()
        #expect(session.loggedWorkout == loggedWorkout)
        let launch = try await relaunch().launch(weightUnit: .pounds)
        #expect(launch.loggedWorkout == loggedWorkout)
    }

    @Test("A delete the store refuses leaves the workout in the log")
    func failedDeleteListed() async throws {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let loggedWorkout = finished(at: 10)
        try await Store(modelContainer: ModelContainer(
            for: Store.schema,
            configurations: ModelConfiguration(schema: Store.schema, url: url),
        )).save(loggedWorkout)
        // The same file opened read-only: its reads work, and its saves throw.
        let readOnly = try ModelContainer(
            for: Store.schema,
            configurations: ModelConfiguration(schema: Store.schema, url: url, allowsSave: false),
        )
        await #expect(throws: (any Error).self) {
            try await Store(modelContainer: readOnly).deleteLoggedWorkout(loggedWorkout.id)
        }
        let session = AppSession(
            workout: workout,
            store: Store(modelContainer: readOnly),
            namer: .muscleGroupsOnly,
        )
        await session.deleteLoggedWorkout(loggedWorkout.id)
        #expect(session.log?.loggedWorkouts == [loggedWorkout])
    }
}
