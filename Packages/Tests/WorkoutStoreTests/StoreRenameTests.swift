import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

/// The rename's chain, from V14, on a store written to disk as a phone holds one.
@Suite("Store rename")
struct StoreRenameTests {
    static func openCurrent(at url: URL) throws -> ModelContainer {
        try ModelContainer(
            for: Store.schema,
            migrationPlan: StoreMigrationPlan.self,
            configurations: ModelConfiguration(schema: Store.schema, url: url),
        )
    }

    @Test("A V14 store written by a shipped build opens renamed, every row, field, and link kept")
    func committedStoreKept() async throws {
        let (url, before) = try StoreRenameFixture.copyCommitted()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(StoreRenameFixture.counts(before) == [
            "workout": 3, "row": 6, "session": 3, "set": 8, "exercise": 2, "customization": 1,
        ])
        let container = try Self.openCurrent(at: url)
        #expect(try StoreRenameFixture.lines(current: ModelContext(container)) == before)

        // And the store reads it: the session in progress on its workout, with its count,
        // pause, and sets; the finished ones; and the exercises.
        let store = Store(modelContainer: container)
        let launch = try await store.launch(weightUnit: .pounds)
        let running = try #require(launch.loggedWorkout)
        #expect(running.isInProgress)
        #expect(running.workoutName == "Upper")
        #expect(launch.workout?.id == running.workoutID)
        #expect(launch.workout?.exercises.count == 3)
        #expect(launch.workout?.exercises.filter { $0.supersetID != nil }.count == 2)
        #expect(running.count?.added == 15)
        #expect(running.pauses.count == 1)
        #expect(running.sets.count == 2)
        #expect(try await store.finishedLoggedWorkouts().map(\.sets.count) == [3, 3])
        #expect(try await store.workoutsByRecency(weightUnit: .pounds).count == 3)
        let list = try await store.exercises()
        #expect(list.exercise(id: "created-1")?.muscleGroups == [.chest, .shoulders])
        #expect(list.exercise(id: "push-up")?.name == "Press-up")
    }

    @Test("The renamed store opens again unchanged, and saves land under the new names")
    func reopensAndSaves() async throws {
        let (url, before) = try StoreRenameFixture.copyCommitted()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        _ = try Self.openCurrent(at: url)
        #expect(try StoreRenameFixture.lines(current: ModelContext(Self.openCurrent(at: url)))
            == before)
        let store = try Store(modelContainer: Self.openCurrent(at: url))
        let running = try #require(try await store.launch(weightUnit: .pounds).loggedWorkout)
        try await store.discardLoggedWorkout(running.id)
        let after = try StoreRenameFixture
            .counts(StoreRenameFixture.lines(current: ModelContext(Self.openCurrent(at: url))))
        #expect(after["session"] == 2)
        #expect(after["set"] == 6)
    }
}
