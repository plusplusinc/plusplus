import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

/// A V13 store on disk: two finished workouts, one with paused time, and one in progress and
/// paused now, each with one set.
private struct V13Store {
    struct Logged {
        let id = UUID()
        let start: Double
        var pausedAt: Double?
        var pausedSeconds = 0.0
        var end: Double?
    }

    static let neverPaused = Logged(start: 10, end: 70)
    static let paused = Logged(start: 100, pausedSeconds: 30, end: 400)
    static let inProgress = Logged(start: 1000, pausedAt: 1100, pausedSeconds: 20)

    let folder = FileManager.default.temporaryDirectory
        .appending(path: "StoreUpgrade-\(UUID().uuidString)")
    var url: URL {
        folder.appending(path: "PlusPlus.store")
    }

    static func at(_ seconds: Double) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    func write() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let schema = Schema(versionedSchema: RoutineSchemaV13.self)
        let old = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, url: url),
        )
        let context = ModelContext(old)
        let workout = RoutineSchemaV7.StoredRoutine(id: UUID())
        workout.name = "Upper"
        workout.editedAt = Self.at(1)
        context.insert(workout)
        let row = RoutineSchemaV7.StoredRoutineExercise(
            id: UUID(),
            exerciseID: "push-up",
            position: 0,
        )
        context.insert(row)
        row.routine = workout
        for seed in [Self.neverPaused, Self.paused, Self.inProgress] {
            let logged = RoutineSchemaV13.StoredWorkout(id: seed.id)
            logged.routineID = workout.id
            logged.routineName = "Upper"
            logged.startedAt = Self.at(seed.start)
            logged.pausedAt = seed.pausedAt.map(Self.at)
            logged.pausedSeconds = seed.pausedSeconds
            logged.endedAt = seed.end.map(Self.at)
            context.insert(logged)
            let set = RoutineSchemaV13.StoredSet(id: UUID())
            set.rowID = row.id
            set.exerciseID = "push-up"
            set.reps = 10
            set.plannedReps = 10
            set.loggedAt = Self.at(seed.start + 5)
            context.insert(set)
            set.workout = logged
        }
        try context.save()
    }
}

extension StoreUpgradeTests {
    @Test("A V13 store opens with every workout intact and no pauses, type, or Health id kept")
    func upgradeBeforeHealth() async throws {
        let old = V13Store()
        defer { try? FileManager.default.removeItem(at: old.folder) }
        try old.write()

        let store = try Self.current(at: old.url)
        let finished = try await store.finishedLoggedWorkouts()
        #expect(finished.map(\.id) == [V13Store.paused.id, V13Store.neverPaused.id])
        #expect(finished.map(\.startedAt) == [V13Store.at(100), V13Store.at(10)])
        #expect(finished.map(\.pausedSeconds) == [30, 0])
        #expect(finished.map(\.endedAt) == [V13Store.at(400), V13Store.at(70)])
        #expect(finished.map(\.sets.count) == [1, 1])
        #expect(finished.allSatisfy { $0.pauses.isEmpty })
        #expect(finished.allSatisfy { $0.healthActivity == nil && $0.healthWorkoutID == nil })
        let running = try #require(try await store.launch(weightUnit: .pounds).loggedWorkout)
        #expect(running.id == V13Store.inProgress.id)
        #expect(running.pausedAt == V13Store.at(1100))
        #expect(running.pausedSeconds == 20)
        #expect(running.pauses.isEmpty)
    }

    @Test("A workout paused across the update keeps each pause after it, and its type, on disk")
    func upgradeThenPauses() async throws {
        let old = V13Store()
        defer { try? FileManager.default.removeItem(at: old.folder) }
        try old.write()

        let store = try Self.current(at: old.url)
        var running = try #require(try await store.launch(weightUnit: .pounds).loggedWorkout)
        running = running.resuming(at: V13Store.at(1150))
            .pausing(at: V13Store.at(1200))
            .resuming(at: V13Store.at(1210))
            .finishing(at: V13Store.at(1300))
        running.healthActivity = .functionalStrength
        try await store.save(running)

        // A second container on the file: what a relaunch reads.
        let reread = try await Self.current(at: old.url).finishedLoggedWorkouts()
        #expect(reread.count == 3)
        let kept = try #require(reread.first { $0.id == V13Store.inProgress.id })
        // The pause under way at the update is kept from its start; the time paused before it
        // is still counted.
        #expect(kept.pauses == [
            DateInterval(start: V13Store.at(1100), end: V13Store.at(1150)),
            DateInterval(start: V13Store.at(1200), end: V13Store.at(1210)),
        ])
        #expect(kept.pausedSeconds == 20 + 50 + 10)
        #expect(kept.endedAt == V13Store.at(1300))
        #expect(kept.healthActivity == .functionalStrength)
        #expect(kept.healthWorkoutID == nil)
    }

    @Test("Pause times read back from a file exactly, so they add up to the time paused")
    func pauseTimesExact() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "StoreUpgrade-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "PlusPlus.store")
        let workout = Workout(name: "Upper")
        try await Self.current(at: url).save(workout, at: V13Store.at(1))
        // Times with no short binary fraction, as a tap's are.
        let finished = LoggedWorkout(
            workoutID: workout.id,
            workoutName: workout.name,
            startedAt: V13Store.at(784_000_000.123_456_7),
        )
        .pausing(at: V13Store.at(784_000_010.1)).resuming(at: V13Store.at(784_000_013.3))
        .pausing(at: V13Store.at(784_000_020.7)).finishing(at: V13Store.at(784_000_029.9))
        try await Self.current(at: url).save(finished)

        let reread = try await Self.current(at: url).finishedLoggedWorkouts()
        #expect(reread == [finished])
        #expect(reread.first?.healthWithheld == nil)
    }
}
