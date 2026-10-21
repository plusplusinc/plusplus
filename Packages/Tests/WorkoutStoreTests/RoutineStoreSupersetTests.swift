import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

/// A relaunch is a second store over the same container: it sees only what was saved.
@Suite("Routine store supersets")
struct RoutineStoreSupersetTests {
    private let container: ModelContainer
    private let rows: [RoutineExercise]

    init() throws {
        container = try WorkoutStoreContainer.make(mode: .inMemory, schema: RoutineStore.schema)
        rows = try ["Push-up", "Plank", "Pull-up", "Goblet squat", "Dumbbell row", "Pull-up"]
            .map { try .builtIn($0) }
    }

    private func relaunch() -> RoutineStore {
        RoutineStore(modelContainer: container)
    }

    /// Plank alone, then a pair, then a triple.
    private func grouped() throws -> Routine {
        var routine = Routine(name: "Supersets", exercises: rows)
        routine = try #require(routine.regrouped(holding: rows[1].id, reaching: rows[2].id)).routine
        routine = try #require(routine.regrouped(holding: rows[3].id, reaching: rows[5].id)).routine
        return routine
    }

    @Test("A pair and a triple reopen as they were, with their rounds")
    func roundTrip() async throws {
        let routine = try grouped()
        try await relaunch().save(routine)
        let reopened = try await relaunch().launch(weightUnit: .pounds).routine
        #expect(reopened == routine)
        #expect(reopened?.joinedToNext == [rows[1].id, rows[3].id, rows[4].id])
    }

    @Test("A cut superset reopens as it was cut, the row left over plain")
    func cutReopens() async throws {
        let store = relaunch()
        var routine = try grouped()
        try await store.save(routine)
        routine = try #require(routine.regrouped(holding: rows[4].id, reaching: rows[3].id)).routine
        try await store.save(routine)
        let reopened = try #require(try await relaunch().launch(weightUnit: .pounds).routine)
        #expect(reopened.joinedToNext == [rows[1].id, rows[3].id])
        #expect(!reopened.isInSuperset(rows[5].id))
    }

    @Test("A broken superset in the store reopens whole, and one of one plain")
    func normalizedOnLoad() async throws {
        var routine = Routine(exercises: Array(rows.prefix(4)))
        let superset = UUID()
        for index in [0, 2, 3] {
            routine.exercises[index].supersetID = superset
        }
        try await relaunch().save(routine)
        let reopened = try #require(try await relaunch().launch(weightUnit: .pounds).routine)
        #expect(reopened.joinedToNext == [rows[2].id])
        #expect(!reopened.isInSuperset(rows[0].id))
    }
}
