import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

/// A relaunch is a second store over the same container: it sees only what was saved.
@Suite("Routine store supersets")
struct StoreSupersetTests {
    private let container: ModelContainer
    private let rows: [WorkoutExercise]

    init() throws {
        container = try WorkoutStoreContainer.make(mode: .inMemory, schema: Store.schema)
        rows = try ["Push-up", "Plank", "Pull-up", "Goblet squat", "Dumbbell row", "Pull-up"]
            .map { try .builtIn($0) }
    }

    private func relaunch() -> Store {
        Store(modelContainer: container)
    }

    /// Plank alone, then a pair, then a triple.
    private func grouped() throws -> Workout {
        var workout = Workout(name: "Supersets", exercises: rows)
        workout = try #require(workout.regrouped(holding: rows[1].id, reaching: rows[2].id)).workout
        workout = try #require(workout.regrouped(holding: rows[3].id, reaching: rows[5].id)).workout
        return workout
    }

    @Test("A pair and a triple reopen as they were, with their rounds")
    func roundTrip() async throws {
        let workout = try grouped()
        try await relaunch().save(workout)
        let reopened = try await relaunch().launch(weightUnit: .pounds).workout
        #expect(reopened == workout)
        #expect(reopened?.joinedToNext == [rows[1].id, rows[3].id, rows[4].id])
    }

    @Test("A superset's rest reopens on every member: set by hand, and kept while automatic")
    func roundRestRoundTrip() async throws {
        var workout = try grouped()
        workout.stepRestAfterRound(of: rows[1].id, by: 1)
        workout.stepRestAfterRound(of: rows[3].id, by: -1)
        workout.setRoundAuto(true, of: rows[3].id)
        try await relaunch().save(workout)
        let reopened = try #require(try await relaunch().launch(weightUnit: .pounds).workout)
        #expect(reopened == workout)
        #expect(!reopened.isRoundAuto(of: rows[2].id))
        #expect(reopened.isRoundAuto(of: rows[5].id))
        var back = reopened
        back.setRoundAuto(false, of: rows[4].id)
        #expect(back.restAfterRound(of: rows[5].id)
            == workout.exercises[3].roundRest.lastByHand)
    }

    @Test("A superset's rest stored by hand with no seconds in range reopens as Auto")
    func roundRestStoredUnset() async throws {
        try await relaunch().save(grouped())
        let context = ModelContext(container)
        for row in try context.fetch(FetchDescriptor<StoredRoutineExercise>())
            where row.supersetID != nil
        {
            row.roundRest = 900
            row.isRoundRestAuto = false
        }
        try context.save()
        let reopened = try #require(try await relaunch().launch(weightUnit: .pounds).workout)
        #expect(reopened.exercises.allSatisfy { $0.roundRest == .neverSet })
        #expect(reopened.isRoundAuto(of: rows[1].id))
    }

    @Test("A cut superset reopens as it was cut, the row left over plain")
    func cutReopens() async throws {
        let store = relaunch()
        var workout = try grouped()
        try await store.save(workout)
        workout = try #require(workout.regrouped(holding: rows[4].id, reaching: rows[3].id)).workout
        try await store.save(workout)
        let reopened = try #require(try await relaunch().launch(weightUnit: .pounds).workout)
        #expect(reopened.joinedToNext == [rows[1].id, rows[3].id])
        #expect(!reopened.isInSuperset(rows[5].id))
    }

    @Test("A broken superset in the store reopens whole, and one of one plain")
    func normalizedOnLoad() async throws {
        var workout = Workout(exercises: Array(rows.prefix(4)))
        let superset = UUID()
        for index in [0, 2, 3] {
            workout.exercises[index].supersetID = superset
        }
        try await relaunch().save(workout)
        let reopened = try #require(try await relaunch().launch(weightUnit: .pounds).workout)
        #expect(reopened.joinedToNext == [rows[2].id])
        #expect(!reopened.isInSuperset(rows[0].id))
    }
}
