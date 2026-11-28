import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

/// What a finished workout keeps for Apple Health, read back by a relaunch: a second store over
/// the same container.
@Suite("Store Health fields")
struct StoreHealthFieldsTests {
    private let container: ModelContainer
    private let workout = Workout(name: "Upper")

    init() throws {
        container = try WorkoutStoreContainer.make(mode: .inMemory, schema: Store.schema)
    }

    private func relaunch() -> Store {
        Store(modelContainer: container)
    }

    private static func at(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    /// A workout finished and saved, and its stored model in `context`.
    private func savedFinished(
        in context: ModelContext,
    ) async throws -> (LoggedWorkout, StoredWorkoutSession) {
        try await relaunch().save(workout, at: Self.at(1))
        let finished = LoggedWorkout(
            workoutID: workout.id,
            workoutName: workout.name,
            startedAt: Self.at(10),
        ).finishing(at: Self.at(100))
        try await relaunch().save(finished)
        let stored = try #require(try context.fetch(FetchDescriptor<StoredWorkoutSession>()).first)
        return (finished, stored)
    }

    @Test(
        "Pause times that don't pair up, or a type unknown, read as none and a save keeps them",
        arguments: [[20.0, 30, 40], [30, 20]],
    )
    func unreadablePausesAndType(times: [Double]) async throws {
        let context = ModelContext(container)
        let (_, stored) = try await savedFinished(in: context)
        stored.healthActivity = "swimming"
        stored.pauseTimes = times.map(Self.at)
        try context.save()
        var read = try #require(try await relaunch().finishedLoggedWorkouts().first)
        #expect(read.pauses.isEmpty)
        #expect(read.healthActivity == nil)
        // A save of what was read, as a rename makes, leaves both as a newer version wrote them.
        read.workoutName = "Upper body"
        try await relaunch().save(read)
        let fresh = ModelContext(container)
        let kept = try #require(try fresh.fetch(FetchDescriptor<StoredWorkoutSession>()).first)
        #expect(kept.workoutName == "Upper body")
        #expect(kept.pauseTimes == times.map(Self.at))
        #expect(kept.healthActivity == "swimming")
    }
}
