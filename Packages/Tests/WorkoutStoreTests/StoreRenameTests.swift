import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

/// The rename's chain, from V14, on a store written to disk as a phone holds one.
@Suite("Store rename")
struct StoreRenameTests {
    static func openCurrent(at url: URL) throws -> ModelContainer {
        try StoreRenameFixture.open(at: url, plan: StoreMigrationPlan.self)
    }

    @Test("A V14 store written by a shipped build opens renamed, every row, field, and link kept")
    func committedStoreKept() async throws {
        let (url, before) = try StoreRenameFixture.copyCommitted()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(StoreRenameFixture.counts(before) == [
            "workout": 3, "row": 6, "session": 3, "set": 8, "exercise": 2, "customization": 1,
        ])
        let container = try StoreRenameBackup.open(at: url)
        #expect(try StoreRenameFixture.lines(current: ModelContext(container)) == before)
        #expect(try StoreRenameBackup.storedEntities(at: url) == [
            "StoredCustomization", "StoredExercise", "StoredLoggedSet", "StoredWorkout",
            "StoredWorkoutExercise", "StoredWorkoutSession",
        ])

        // And the store reads it: the session in progress on its workout, with its count,
        // pause, and sets; the finished ones; and the exercises.
        let store = Store(modelContainer: container)
        let launch = try await store.launch(weightUnit: .pounds)
        let running = try #require(launch.workoutSession)
        #expect(running.isInProgress)
        #expect(running.workoutName == "Upper")
        #expect(launch.workout?.id == running.workoutID)
        #expect(launch.workout?.exercises.count == 3)
        #expect(launch.workout?.exercises.filter { $0.supersetID != nil }.count == 2)
        #expect(running.count?.added == 15)
        #expect(running.pauses.count == 1)
        #expect(running.sets.count == 2)
        #expect(try await store.finishedWorkoutSessions().map(\.sets.count) == [3, 3])
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
        #expect(try StoreRenameFixture.currentLines(at: url) == before)
        let store = try Store(modelContainer: Self.openCurrent(at: url))
        let running = try #require(try await store.launch(weightUnit: .pounds).workoutSession)
        try await store.discardWorkoutSession(running.id)
        let after = try StoreRenameFixture.counts(StoreRenameFixture.currentLines(at: url))
        #expect(after["session"] == 2)
        #expect(after["set"] == 6)
    }

    @Test(
        "An empty workout, a row and a set with no parent, and two sessions of one id come through",
    )
    func oddShapesKept() throws {
        typealias Fixture = StoreRenameFixture
        let folder = try Fixture.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "PlusPlus.store")
        let before: [String]
        do {
            let schema = Schema(versionedSchema: RoutineSchemaV14.self)
            let old = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url),
            )
            let context = ModelContext(old)
            context.insert(Fixture.OldWorkout(id: UUID()))
            let loose = Fixture.OldRow(id: UUID(), exerciseID: "push-up", position: 0)
            context.insert(loose)
            Fixture.insertSets(1, in: nil, rows: [loose], context: context)
            let sharedID = UUID()
            for start in [1.0, 2.0] {
                let session = Fixture.OldSession(id: sharedID)
                session.startedAt = Fixture.at(start)
                session.endedAt = Fixture.at(start + 1)
                context.insert(session)
                Fixture.insertSets(1, in: session, rows: [loose], context: context)
            }
            try context.save()
            before = try Fixture.lines(old: context)
        }
        #expect(Fixture.counts(before) == ["workout": 1, "row": 1, "session": 2, "set": 3])

        let container = try StoreRenameBackup.open(at: url)
        #expect(try Fixture.lines(current: ModelContext(container)) == before)
    }

    @Test(
        "A V1 store opens through the backup: brought to V14, counted, renamed, and the copy gone",
    )
    func oldestThroughBackup() async throws {
        let folder = try StoreRenameFixture.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "PlusPlus.store")
        let workoutID = UUID()
        do {
            let schema = Schema(versionedSchema: RoutineSchemaV1.self)
            let old = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url),
            )
            let context = ModelContext(old)
            let workout = RoutineSchemaV1.StoredRoutine(id: workoutID)
            workout.name = "Upper"
            context.insert(workout)
            let row = RoutineSchemaV1.StoredRoutineExercise(
                id: UUID(),
                exerciseID: "push-up",
                position: 0,
            )
            context.insert(row)
            row.routine = workout
            try context.save()
        }

        let store = try Store(modelContainer: StoreRenameBackup.open(at: url))
        let workout = try #require(try await store.launch(weightUnit: .pounds).workout)
        #expect(workout.id == workoutID)
        #expect(workout.name == "Upper")
        #expect(workout.exercises.map(\.exercise.id) == ["push-up"])
        #expect(!StoreRenameFixture.exists(StoreRenameBackup.folder(for: url)))
    }
}
