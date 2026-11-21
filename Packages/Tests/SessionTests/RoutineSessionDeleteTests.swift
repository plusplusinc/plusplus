import Foundation
import SwiftData
import Testing
@testable import Session
@testable import WorkoutStore

/// Deleting a routine through the session: a listed one leaves the list, the open one leaves
/// the session on a new routine with the Routines screen showing, and a relaunch never brings
/// either back. A relaunch is a second store over the same container.
@Suite("Routine session delete")
struct RoutineSessionDeleteTests {
    private let container: ModelContainer
    private let lower = Routine(name: "Lower")

    init() async throws {
        container = try WorkoutStoreContainer.make(mode: .inMemory, schema: RoutineStore.schema)
        try await relaunch().save(lower, at: Date(timeIntervalSinceReferenceDate: 1))
    }

    private func relaunch() -> RoutineStore {
        RoutineStore(modelContainer: container)
    }

    private func session(_ routine: Routine) -> RoutineSession {
        RoutineSession(routine: routine, store: relaunch(), namer: .muscleGroupsOnly)
    }

    private static func upper() throws -> Routine {
        let exercise = try #require(Exercise.builtIn(id: "barbell-bench-press"))
        return Routine(
            name: "Upper",
            exercises: [RoutineExercise(exercise: exercise, weightUnit: .pounds)],
        )
    }

    private func storedIDs() async throws -> [Routine.ID] {
        try await relaunch().routinesByRecency(weightUnit: .pounds).map(\.id)
    }

    @Test("A listed routine deleted from Routines leaves the list and the store")
    func deleteListed() async throws {
        let upper = try Self.upper()
        let session = session(upper)
        session.save(upper)
        session.showRoutines()
        await session.refreshRecent(weightUnit: .pounds)
        await session.delete(lower.id)
        #expect(session.recent.map(\.id) == [upper.id])
        #expect(session.screen == .routines)
        #expect(session.current == upper)
        await session.writesLanded()
        #expect(try await storedIDs() == [upper.id])
    }

    @Test("Deleting the open routine lands its last edit first, so no save brings it back")
    func deleteOpenAfterEdit() async throws {
        let upper = try Self.upper()
        let session = session(Routine())
        session.save(upper)
        await session.delete(upper.id)
        await session.writesLanded()
        #expect(try await storedIDs() == [lower.id])
    }

    @Test("Deleting the open routine at the root shows Routines on a new, empty routine")
    func deleteOpenAtRoot() async throws {
        let upper = try Self.upper()
        try await relaunch().save(upper)
        let session = session(upper)
        await session.delete(upper.id)
        #expect(session.screen == .routines)
        #expect(session.current.isEmpty)
        #expect(session.opened == session.current)
        #expect(session.current.id != upper.id)
        #expect(!session.recent.contains { $0.id == upper.id })
    }

    @Test("Deleting a pushed routine pops back to Routines on a new, empty routine")
    func deletePushed() async throws {
        let session = session(Routine())
        session.showRoutines()
        await session.open(lower.id, weightUnit: .pounds)
        #expect(session.screen == .pushedRoutine)
        await session.delete(lower.id)
        #expect(session.screen == .routines)
        #expect(session.current.isEmpty)
        #expect(try await storedIDs().isEmpty)
    }

    @Test("The routine a workout runs on can't be deleted, nor one with nothing saved")
    func refusals() throws {
        let upper = try Self.upper()
        let session = session(upper)
        #expect(session.canDeleteOpen)
        session.start(on: upper.id)
        #expect(!session.canDeleteOpen)
        #expect(!self.session(Routine()).canDeleteOpen)
    }

    @Test("A delete asked during a workout on that routine keeps it")
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

    @Test("A finished workout on the deleted routine is still stored")
    func loggedWorkoutKept() async throws {
        let upper = try Self.upper()
        let session = session(upper)
        session.save(upper)
        session.start(on: upper.id, at: Date(timeIntervalSinceReferenceDate: 10))
        session.finish(at: Date(timeIntervalSinceReferenceDate: 20))
        await session.delete(upper.id)
        await session.writesLanded()
        let loggedWorkouts = try ModelContext(container).fetch(FetchDescriptor<StoredWorkout>())
        #expect(loggedWorkouts.map(\.loggedWorkout.routineID) == [upper.id])
        #expect(loggedWorkouts.allSatisfy { !$0.loggedWorkout.isInProgress })
    }
}
