import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

/// Where the app opens, one row per state: a new workout with none saved, the workout in
/// progress, the workout last opened or edited, and the Workouts list after a finish. A relaunch
/// is a second store over the same container; dates are explicit.
@Suite("Store launch")
struct StoreLaunchTests {
    private let container: ModelContainer

    init() throws {
        container = try WorkoutStoreContainer.make(mode: .inMemory, schema: Store.schema)
    }

    private func relaunch() -> Store {
        Store(modelContainer: container)
    }

    private func launch() async throws -> Store.Launch {
        try await relaunch().launch(weightUnit: .pounds)
    }

    private static func at(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    private static func finished(
        _ workout: Workout,
        from start: TimeInterval,
        to end: TimeInterval,
    ) -> LoggedWorkout {
        LoggedWorkout(workoutID: workout.id, workoutName: workout.name, startedAt: at(start))
            .finishing(at: at(end))
    }

    @Test("With no saved workout, a new one opens")
    func noSavedWorkouts() async throws {
        #expect(try await launch() == .newWorkout)
    }

    @Test("With no saved workout left, a new one opens, even after a finish")
    func lastWorkoutDeleted() async throws {
        let workout = Workout(name: "Upper")
        let store = relaunch()
        try await store.save(workout, at: Self.at(1))
        try await store.save(Self.finished(workout, from: 10, to: 20))
        try await store.deleteWorkout(workout.id)
        #expect(try await launch() == .newWorkout)
    }

    @Test("A workout in progress opens on that workout")
    func inProgress() async throws {
        let workout = Workout(name: "Upper")
        let store = relaunch()
        try await store.save(workout, at: Self.at(1))
        try await store.save(Self.finished(workout, from: 10, to: 20))
        let running = LoggedWorkout(
            workoutID: workout.id,
            workoutName: workout.name,
            startedAt: Self.at(30),
        )
        try await store.save(running)
        #expect(try await launch() == .inProgress(workout, running))
    }

    @Test("The workout last opened or edited opens, with nothing finished since")
    func lastOpenedOrEdited() async throws {
        var workout = Workout(name: "Upper")
        let other = Workout(name: "Lower")
        let store = relaunch()
        try await store.save(other, at: Self.at(1))
        try await store.save(workout, at: Self.at(2))
        #expect(try await launch() == .workout(workout))
        _ = try await store.openWorkout(other.id, weightUnit: .pounds, at: Self.at(3))
        #expect(try await launch() == .workout(other))
        workout.name = "Upper again"
        try await store.save(workout, at: Self.at(4))
        #expect(try await launch() == .workout(workout))
    }

    @Test("A finish after the last open or edit, with saved workouts, opens the Workouts list")
    func afterFinish() async throws {
        let workout = Workout(name: "Upper")
        let store = relaunch()
        try await store.save(workout, at: Self.at(1))
        try await store.save(Workout(name: "Lower"), at: Self.at(2))
        try await store.save(Self.finished(workout, from: 10, to: 20))
        #expect(try await launch() == .workouts)
    }

    @Test("A workout opened after a finish opens, the one opened last")
    func openedAfterFinish() async throws {
        let workout = Workout(name: "Upper")
        let other = Workout(name: "Lower")
        let store = relaunch()
        try await store.save(workout, at: Self.at(1))
        try await store.save(other, at: Self.at(2))
        try await store.save(Self.finished(workout, from: 10, to: 20))
        _ = try await store.openWorkout(other.id, weightUnit: .pounds, at: Self.at(30))
        #expect(try await launch() == .workout(other))
    }

    @Test(
        "With the last finish deleted, an earlier finish after the last open still opens the list",
    )
    func deletedFinishEarlierFinishRemains() async throws {
        let workout = Workout(name: "Upper")
        let store = relaunch()
        try await store.save(workout, at: Self.at(1))
        try await store.save(Self.finished(workout, from: 10, to: 20))
        let latest = Self.finished(workout, from: 30, to: 40)
        try await store.save(latest)
        try await store.deleteLoggedWorkout(latest.id)
        #expect(try await launch() == .workouts)
    }

    @Test("With the last finish deleted, the workout opened since the one left opens")
    func deletedFinishOpenedSince() async throws {
        let workout = Workout(name: "Upper")
        let store = relaunch()
        try await store.save(workout, at: Self.at(1))
        try await store.save(Self.finished(workout, from: 10, to: 20))
        _ = try await store.openWorkout(workout.id, weightUnit: .pounds, at: Self.at(30))
        let latest = Self.finished(workout, from: 40, to: 50)
        try await store.save(latest)
        #expect(try await launch() == .workouts)
        try await store.deleteLoggedWorkout(latest.id)
        #expect(try await launch() == .workout(workout))
    }
}
