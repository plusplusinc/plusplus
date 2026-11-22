import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

/// Deleting a workout by id: it is gone after a relaunch, its rows with it, and its logged workouts
/// stay. Deleting a finished logged workout takes its sets and leaves its workout. A relaunch is a
/// second store over the same container.
@Suite("Workout store delete")
struct StoreDeleteTests {
    private let container: ModelContainer

    init() throws {
        container = try WorkoutStoreContainer.make(mode: .inMemory, schema: Store.schema)
    }

    private func relaunch() -> Store {
        Store(modelContainer: container)
    }

    private static func at(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    @Test("A deleted workout is gone after a relaunch, its rows with it, the others kept")
    func deletedIsGone() async throws {
        let upper = try Workout(name: "Upper", exercises: [.builtIn("Barbell bench press")])
        let lower = Workout(name: "Lower")
        try await relaunch().save(lower, at: Self.at(1))
        try await relaunch().save(upper, at: Self.at(2))
        try await relaunch().deleteWorkout(upper.id)
        #expect(try await relaunch().workoutsByRecency(weightUnit: .pounds) == [lower])
        let rows = try ModelContext(container).fetch(FetchDescriptor<StoredRoutineExercise>())
        #expect(rows.isEmpty)
    }

    @Test("A finished logged workout of a deleted workout is still stored")
    func loggedWorkoutsStay() async throws {
        let upper = Workout(name: "Upper")
        try await relaunch().save(upper, at: Self.at(1))
        let loggedWorkout = LoggedWorkout(
            workoutID: upper.id,
            workoutName: upper.name,
            startedAt: Self.at(10),
        )
        .finishing(at: Self.at(20))
        try await relaunch().save(loggedWorkout)
        try await relaunch().deleteWorkout(upper.id)
        let stored = try ModelContext(container).fetch(FetchDescriptor<StoredWorkout>())
        #expect(stored.map(\.loggedWorkout) == [loggedWorkout])
    }

    @Test("Launch after the last-opened workout is deleted opens the next most recent")
    func launchAfterDelete() async throws {
        let lower = Workout(name: "Lower")
        let upper = Workout(name: "Upper")
        try await relaunch().save(lower, at: Self.at(1))
        try await relaunch().save(upper, at: Self.at(2))
        try await relaunch().deleteWorkout(upper.id)
        #expect(try await relaunch().launch(weightUnit: .pounds).workout == lower)
    }

    @Test("Deleting a workout that isn't stored changes nothing")
    func deleteMissing() async throws {
        let lower = Workout(name: "Lower")
        try await relaunch().save(lower, at: Self.at(1))
        try await relaunch().deleteWorkout(UUID())
        #expect(try await relaunch().workoutsByRecency(weightUnit: .pounds) == [lower])
    }

    @Test("A finished logged workout deleted from Log is gone after a relaunch, its sets with it")
    func loggedWorkoutDeleted() async throws {
        let row = try WorkoutExercise.builtIn("Push-up")
        let upper = Workout(name: "Upper", exercises: [row])
        try await relaunch().save(upper, at: Self.at(1))
        func finished(at seconds: TimeInterval) -> LoggedWorkout {
            LoggedWorkout(workoutID: upper.id, workoutName: upper.name, startedAt: Self.at(seconds))
                .logging(PlannedSet(row: row.id, round: 1), of: row, at: Self.at(seconds + 10))
                .finishing(at: Self.at(seconds + 20))
        }
        let deleted = finished(at: 10)
        let kept = finished(at: 40)
        try await relaunch().save(deleted)
        try await relaunch().save(kept)
        try await relaunch().deleteLoggedWorkout(deleted.id)
        #expect(try await relaunch().finishedLoggedWorkouts() == [kept])
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<StoredSet>()) == 1)
        #expect(try await relaunch().workoutsByRecency(weightUnit: .pounds) == [upper])
        try await relaunch().deleteLoggedWorkout(deleted.id)
    }

    @Test("A logged workout still in progress is never deleted from Log; only Discard ends it")
    func loggedWorkoutInProgressKept() async throws {
        let upper = Workout(name: "Upper")
        try await relaunch().save(upper, at: Self.at(1))
        let running = LoggedWorkout(
            workoutID: upper.id,
            workoutName: "Upper",
            startedAt: Self.at(10),
        )
        try await relaunch().save(running)
        try await relaunch().deleteLoggedWorkout(running.id)
        #expect(try await relaunch().launch(weightUnit: .pounds).loggedWorkout == running)
    }
}
