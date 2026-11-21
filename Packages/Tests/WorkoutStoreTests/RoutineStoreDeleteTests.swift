import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

/// Deleting a routine by id: it is gone after a relaunch, its rows with it, and its workouts
/// stay. A relaunch is a second store over the same container.
@Suite("Routine store delete")
struct RoutineStoreDeleteTests {
    private let container: ModelContainer

    init() throws {
        container = try WorkoutStoreContainer.make(mode: .inMemory, schema: RoutineStore.schema)
    }

    private func relaunch() -> RoutineStore {
        RoutineStore(modelContainer: container)
    }

    private static func at(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    @Test("A deleted routine is gone after a relaunch, its rows with it, the others kept")
    func deletedIsGone() async throws {
        let upper = try Routine(name: "Upper", exercises: [.builtIn("Barbell bench press")])
        let lower = Routine(name: "Lower")
        try await relaunch().save(lower, at: Self.at(1))
        try await relaunch().save(upper, at: Self.at(2))
        try await relaunch().deleteRoutine(upper.id)
        #expect(try await relaunch().routinesByRecency(weightUnit: .pounds) == [lower])
        let rows = try ModelContext(container).fetch(FetchDescriptor<StoredRoutineExercise>())
        #expect(rows.isEmpty)
    }

    @Test("A finished workout on a deleted routine is still stored")
    func loggedWorkoutsStay() async throws {
        let upper = Routine(name: "Upper")
        try await relaunch().save(upper, at: Self.at(1))
        let loggedWorkout = LoggedWorkout(
            routineID: upper.id,
            routineName: upper.name,
            startedAt: Self.at(10),
        )
        .finishing(at: Self.at(20))
        try await relaunch().save(loggedWorkout)
        try await relaunch().deleteRoutine(upper.id)
        let stored = try ModelContext(container).fetch(FetchDescriptor<StoredWorkout>())
        #expect(stored.map(\.loggedWorkout) == [loggedWorkout])
    }

    @Test("Launch after the last-opened routine is deleted opens the next most recent")
    func launchAfterDelete() async throws {
        let lower = Routine(name: "Lower")
        let upper = Routine(name: "Upper")
        try await relaunch().save(lower, at: Self.at(1))
        try await relaunch().save(upper, at: Self.at(2))
        try await relaunch().deleteRoutine(upper.id)
        #expect(try await relaunch().launch(weightUnit: .pounds).routine == lower)
    }

    @Test("Deleting a routine that isn't stored changes nothing")
    func deleteMissing() async throws {
        let lower = Routine(name: "Lower")
        try await relaunch().save(lower, at: Self.at(1))
        try await relaunch().deleteRoutine(UUID())
        #expect(try await relaunch().routinesByRecency(weightUnit: .pounds) == [lower])
    }
}
