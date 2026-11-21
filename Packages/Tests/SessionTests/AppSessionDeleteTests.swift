import Foundation
import SwiftData
import Testing
@testable import Session
@testable import WorkoutStore

/// Deleting a workout through the session: a listed one leaves the list, the open one leaves
/// the session on a new workout with the Workouts screen showing, and a relaunch never brings
/// either back. A relaunch is a second store over the same container.
@Suite("Workout session delete")
struct AppSessionDeleteTests {
    private let container: ModelContainer
    private let lower = Workout(name: "Lower")

    init() async throws {
        container = try WorkoutStoreContainer.make(mode: .inMemory, schema: Store.schema)
        try await relaunch().save(lower, at: Date(timeIntervalSinceReferenceDate: 1))
    }

    private func relaunch() -> Store {
        Store(modelContainer: container)
    }

    private func session(_ workout: Workout) -> AppSession {
        AppSession(workout: workout, store: relaunch(), namer: .muscleGroupsOnly)
    }

    private static func upper() throws -> Workout {
        let exercise = try #require(Exercise.builtIn(id: "barbell-bench-press"))
        return Workout(
            name: "Upper",
            exercises: [WorkoutExercise(exercise: exercise, weightUnit: .pounds)],
        )
    }

    private func storedIDs() async throws -> [Workout.ID] {
        try await relaunch().workoutsByRecency(weightUnit: .pounds).map(\.id)
    }

    @Test("A listed workout deleted from Workouts leaves the list and the store")
    func deleteListed() async throws {
        let upper = try Self.upper()
        let session = session(upper)
        session.save(upper)
        session.showWorkouts()
        await session.refreshRecent(weightUnit: .pounds)
        await session.delete(lower.id)
        #expect(session.recent.map(\.id) == [upper.id])
        #expect(session.screen == .workouts)
        #expect(session.current == upper)
        await session.writesLanded()
        #expect(try await storedIDs() == [upper.id])
    }

    @Test("Deleting the open workout lands its last edit first, so no save brings it back")
    func deleteOpenAfterEdit() async throws {
        let upper = try Self.upper()
        let session = session(Workout())
        session.save(upper)
        await session.delete(upper.id)
        await session.writesLanded()
        #expect(try await storedIDs() == [lower.id])
    }

    @Test("Deleting the open workout at the root shows Workouts on a new, empty workout")
    func deleteOpenAtRoot() async throws {
        let upper = try Self.upper()
        try await relaunch().save(upper)
        let session = session(upper)
        await session.delete(upper.id)
        #expect(session.screen == .workouts)
        #expect(session.current.isEmpty)
        #expect(session.opened == session.current)
        #expect(session.current.id != upper.id)
        #expect(!session.recent.contains { $0.id == upper.id })
    }

    @Test("Deleting a pushed workout pops back to Workouts on a new, empty workout")
    func deletePushed() async throws {
        let session = session(Workout())
        session.showWorkouts()
        await session.open(lower.id, weightUnit: .pounds)
        #expect(session.screen == .pushedWorkout)
        await session.delete(lower.id)
        #expect(session.screen == .workouts)
        #expect(session.current.isEmpty)
        #expect(try await storedIDs().isEmpty)
    }

    @Test("A workout in progress can't be deleted, nor one with nothing saved")
    func refusals() throws {
        let upper = try Self.upper()
        let session = session(upper)
        #expect(session.canDeleteOpen)
        session.start(on: upper.id)
        #expect(!session.canDeleteOpen)
        #expect(!self.session(Workout()).canDeleteOpen)
    }

    @Test("A delete asked while that workout is in progress keeps it")
    func refusedDuringLiveWorkout() async throws {
        let upper = try Self.upper()
        let session = session(upper)
        session.save(upper)
        session.start(on: upper.id)
        await session.delete(upper.id)
        #expect(session.current == upper)
        await session.writesLanded()
        #expect(try await storedIDs().contains(upper.id))
    }

    @Test("A finished logged workout of the deleted workout is still stored")
    func loggedWorkoutKept() async throws {
        let upper = try Self.upper()
        let session = session(upper)
        session.save(upper)
        session.start(on: upper.id, at: Date(timeIntervalSinceReferenceDate: 10))
        session.finish(at: Date(timeIntervalSinceReferenceDate: 20))
        await session.delete(upper.id)
        await session.writesLanded()
        let loggedWorkouts = try ModelContext(container).fetch(FetchDescriptor<StoredWorkout>())
        #expect(loggedWorkouts.map(\.loggedWorkout.workoutID) == [upper.id])
        #expect(loggedWorkouts.allSatisfy { !$0.loggedWorkout.isInProgress })
    }
}
