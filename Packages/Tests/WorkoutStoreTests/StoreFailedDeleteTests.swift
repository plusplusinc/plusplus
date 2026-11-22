import Foundation
import SQLite3
import SwiftData
import Testing
@testable import WorkoutStore

/// A delete whose save fails is undone in the store that tried it: the call throws, a read right
/// after still returns what it would have deleted, and a later save of something else, which
/// succeeds, doesn't land the delete. A relaunch is a second store over the same file.
@Suite("Workout store, a delete that doesn't save")
final class StoreFailedDeleteTests {
    // A folder of its own, so its removal takes SQLite's files beside the store too.
    private let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
    private let url: URL
    private let container: ModelContainer

    init() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appending(path: "PlusPlus.store")
        container = try ModelContainer(
            for: Store.schema,
            configurations: ModelConfiguration(schema: Store.schema, url: url),
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    private func relaunch() -> Store {
        Store(modelContainer: container)
    }

    private static func at(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    /// Refuses every save to the file until `allowSaves()`. A SQLite trigger, set from a
    /// connection of its own, aborts the row each save adds to the store's change history
    /// (Core Data's `ATRANSACTION` table), so the save fails as a whole, whatever it changes, and
    /// nothing of it lands, as a full disk or a store opened read-only would.
    private func refuseSaves() throws {
        try execute("""
        CREATE TRIGGER refuse_saves BEFORE INSERT ON ATRANSACTION
        BEGIN SELECT RAISE(ABORT, 'saves refused'); END
        """)
    }

    private func allowSaves() throws {
        try execute("DROP TRIGGER refuse_saves")
    }

    private func execute(_ sql: String) throws {
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        guard sqlite3_open(url.path, &database) == SQLITE_OK,
              sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK
        else {
            throw SQLiteFailure(message: String(cString: sqlite3_errmsg(database)))
        }
    }

    private struct SQLiteFailure: Error {
        let message: String
    }

    @Test("A workout delete that fails leaves the workout and its rows, after a later save too")
    func deleteWorkout() async throws {
        let upper = try Workout(name: "Upper", exercises: [.builtIn("Barbell bench press")])
        let store = relaunch()
        try await store.save(upper, at: Self.at(1))
        try refuseSaves()
        await #expect(throws: (any Error).self) { try await store.deleteWorkout(upper.id) }
        #expect(try await store.workout(upper.id, weightUnit: .pounds) == upper)
        try allowSaves()
        try await store.save(Workout(name: "Lower"), at: Self.at(2))
        #expect(try await relaunch().workout(upper.id, weightUnit: .pounds) == upper)
    }

    @Test("A discard that fails leaves the logged workout, its sets, and its cleared workout")
    func discardLoggedWorkout() async throws {
        let row = try WorkoutExercise.builtIn("Push-up")
        // Cleared to nothing while it runs: the discard would delete it in the same save.
        let cleared = Workout()
        let store = relaunch()
        try await store.save(cleared, at: Self.at(1), keepsEmpty: true)
        let running = LoggedWorkout(workoutID: cleared.id, workoutName: "", startedAt: Self.at(10))
            .logging(PlannedSet(row: row.id, round: 1), of: row, at: Self.at(20))
        try await store.save(running)
        try refuseSaves()
        await #expect(throws: (any Error).self) { try await store.discardLoggedWorkout(running.id) }
        #expect(try await store.launch(weightUnit: .pounds).loggedWorkout == running)
        #expect(try await store.workout(cleared.id, weightUnit: .pounds) == cleared)
        try allowSaves()
        try await store.save(Workout(name: "Lower"), at: Self.at(30))
        let launch = try await relaunch().launch(weightUnit: .pounds)
        #expect(launch.loggedWorkout == running)
        #expect(launch.loggedWorkout?.sets.count == 1)
        #expect(try await relaunch().workout(cleared.id, weightUnit: .pounds) == cleared)
    }

    @Test("An exercise delete that fails leaves the exercise, its rows, and the workout it empties")
    func deleteExercise() async throws {
        let curl = CreatedExercise(
            name: "Cable curl",
            muscleGroups: [.arms],
            equipment: [.dumbbells],
        )
        let curlRow = WorkoutExercise(exercise: Exercise(created: curl), weightUnit: .pounds)
        let named = try Workout(name: "Arms", exercises: [curlRow, .builtIn("Push-up")])
        // Nothing but the curl: the delete would delete it with its row.
        let emptied = Workout(exercises: [
            WorkoutExercise(exercise: Exercise(created: curl), weightUnit: .pounds),
        ])
        let store = relaunch()
        try await store.save(curl)
        try await store.save(named, at: Self.at(1))
        try await store.save(emptied, at: Self.at(2))
        func expectKept(by store: Store) async throws {
            #expect(try await store.exercises() == ExerciseList(created: [curl]))
            #expect(try await store.workout(named.id, weightUnit: .pounds) == named)
            #expect(try await store.workout(emptied.id, weightUnit: .pounds) == emptied)
        }
        try refuseSaves()
        await #expect(throws: (any Error).self) { try await store.deleteExercise(curl.id) }
        try await expectKept(by: store)
        try allowSaves()
        try await store.save(Workout(name: "Lower"), at: Self.at(3))
        try await expectKept(by: relaunch())
    }
}
