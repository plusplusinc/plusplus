import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

/// What Apple Health is owed, read from the store, and the one write of Health's id.
@Suite("Store Health owed")
struct StoreHealthOwedTests {
    private static func at(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    private static func finished(
        _ start: Double,
        _ end: Double,
        pausedSeconds: Double = 0,
    ) -> LoggedWorkout {
        LoggedWorkout(
            workoutID: UUID(),
            workoutName: "Upper",
            startedAt: at(start),
            pausedSeconds: pausedSeconds,
        ).finishing(at: at(end))
    }

    @Test("Owed is every finished workout with no Health id that Health can have, earliest first")
    func owedOrderAndRule() async throws {
        let store = try Store(modelContainer: WorkoutStoreContainer.make(
            mode: .inMemory,
            schema: Store.schema,
        ))
        let later = Self.finished(500, 600)
        let earlier = Self.finished(100, 200)
        let marked = Self.finished(300, 400)
        // Paused before the store kept a pause's times: withheld.
        let pausedBefore = Self.finished(700, 800, pausedSeconds: 30)
        let noLength = Self.finished(900, 900)
        let inProgress = LoggedWorkout(workoutID: UUID(), workoutName: "", startedAt: Self.at(1000))
        for workout in [later, earlier, marked, pausedBefore, noLength, inProgress] {
            try await store.save(workout)
        }
        try await store.markInHealth(marked.id, as: UUID())
        let owed = try await store.owedToHealth()
        #expect(owed.map(\.id) == [earlier.id, later.id])
    }

    @Test("Marking a workout that is gone does nothing")
    func markGone() async throws {
        let store = try Store(modelContainer: WorkoutStoreContainer.make(
            mode: .inMemory,
            schema: Store.schema,
        ))
        let kept = Self.finished(100, 200)
        try await store.save(kept)
        try await store.markInHealth(UUID(), as: UUID())
        #expect(try await store.owedToHealth().map(\.id) == [kept.id])
    }

    @Test("Health's id survives a relaunch, and a save from a copy read before it was kept")
    func markOnDisk() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "StoreHealthOwed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "PlusPlus.store")
        let finished = Self.finished(100, 200)
        let healthID = UUID()
        do {
            let store = try StoreUpgradeTests.current(at: url)
            try await store.save(finished)
            try await store.markInHealth(finished.id, as: healthID)
            // The copy in memory from before the mark, saved again, as a rename makes.
            var older = finished
            older.workoutName = "Upper body"
            try await store.save(older)
        }
        let relaunched = try StoreUpgradeTests.current(at: url)
        let read = try #require(try await relaunched.finishedLoggedWorkouts().first)
        #expect(read.workoutName == "Upper body")
        #expect(read.healthWorkoutID == healthID)
        #expect(try await relaunched.owedToHealth().isEmpty)
    }
}
