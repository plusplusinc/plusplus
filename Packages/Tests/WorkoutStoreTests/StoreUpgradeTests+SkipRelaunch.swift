import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

/// A V12 store as a build before the skip's clock wrote it, opened under today's shape, and a
/// skip made after that, read back by a second launch from the file.
extension StoreUpgradeTests {
    private typealias V12 = RoutineSchemaV12

    /// A set to write: its row, the clock at its log, and its rest's adjustment.
    private struct Logged {
        let row: RoutineSchemaV7.StoredRoutineExercise
        let clock: Double
        let adjustment: Int

        init(_ row: RoutineSchemaV7.StoredRoutineExercise, _ clock: Double, _ adjustment: Int) {
            self.row = row
            self.clock = clock
            self.adjustment = adjustment
        }
    }

    /// A workout as V12 stored it, its sets logged in order.
    private static func insert(
        _ workout: V12.StoredWorkout,
        sets: [Logged],
        in context: ModelContext,
    ) {
        workout.routineID = sets.first?.row.routine?.id
        workout.routineName = "Upgrade"
        context.insert(workout)
        for (position, logged) in sets.enumerated() {
            let set = V12.StoredSet(id: UUID())
            set.rowID = logged.row.id
            set.exerciseID = logged.row.exerciseID
            set.position = position
            set.round = position % 2 + 1
            set.reps = logged.row.reps
            set.plannedReps = logged.row.reps
            set.seconds = logged.row.seconds.map { _ in 12 }
            set.plannedSeconds = logged.row.seconds
            set.loggedAt = workout.startedAt.addingTimeInterval(logged.clock)
            set.clockWhenLogged = logged.clock
            set.restAdjustment = logged.adjustment
            context.insert(set)
            set.workout = workout
        }
    }

    /// Writes, as V12 did, push-ups then a plank, 2 sets each resting 60 s; a finished workout
    /// on them with three rests skipped (each a cut); and one in progress with a rest skipped,
    /// then one given +15 s, still running.
    private static func writeV12(at url: URL) throws {
        let schema = Schema(versionedSchema: V12.self)
        let old = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, url: url),
        )
        let context = ModelContext(old)
        let workout = RoutineSchemaV7.StoredRoutine(id: UUID())
        workout.name = "Upgrade"
        workout.editedAt = Date(timeIntervalSinceReferenceDate: 1)
        context.insert(workout)
        let rows = ["push-up", "plank"].enumerated().map { position, exercise in
            let row = RoutineSchemaV7.StoredRoutineExercise(
                id: UUID(),
                exerciseID: exercise,
                position: position,
            )
            row.sets = 2
            row.rest = 60
            row.isRestAuto = false
            row.reps = exercise == "plank" ? nil : 10
            row.seconds = exercise == "plank" ? 30 : nil
            context.insert(row)
            row.routine = workout
            return row
        }
        let finished = V12.StoredWorkout(id: UUID())
        finished.startedAt = Date(timeIntervalSinceReferenceDate: 1000)
        finished.endedAt = Date(timeIntervalSinceReferenceDate: 1066)
        insert(
            finished,
            sets: [
                Logged(rows[0], 7, -50), Logged(rows[0], 20, -52),
                Logged(rows[1], 45, -24), Logged(rows[1], 55, 0),
            ],
            in: context,
        )
        let running = V12.StoredWorkout(id: UUID())
        running.startedAt = Date(timeIntervalSinceReferenceDate: 2000)
        insert(running, sets: [Logged(rows[0], 2, -56), Logged(rows[0], 9, 15)], in: context)
        try context.save()
    }

    /// A launch's store: today's shape on a new container over the file.
    static func current(at url: URL) throws -> Store {
        try Store(modelContainer: ModelContainer(
            for: Store.schema,
            migrationPlan: StoreMigrationPlan.self,
            configurations: ModelConfiguration(schema: Store.schema, url: url),
        ))
    }

    /// Expects `writeV12`'s two logged workouts as V12 stored them, with no rest skipped.
    private static func expectAsWritten(running: WorkoutSession, finished: [WorkoutSession]) {
        #expect(running.startedAt == Date(timeIntervalSinceReferenceDate: 2000))
        #expect(running.count == nil)
        #expect(running.sets.map(\.restSkippedAt) == [nil, nil])
        #expect(running.sets.map(\.restAdjustment) == [-56, 15])
        #expect(running.sets.map(\.clockWhenLogged) == [2, 9])
        #expect(running.sets.map(\.target) == [.reps(10), .reps(10)])
        #expect(finished.count == 1)
        #expect(finished.first?.endedAt == Date(timeIntervalSinceReferenceDate: 1066))
        #expect(finished.first?.sets.map(\.restSkippedAt) == [nil, nil, nil, nil])
        #expect(finished.first?.sets.map(\.restAdjustment) == [-50, -52, -24, 0])
        #expect(finished.first?.sets.map(\.clockWhenLogged) == [7, 20, 45, 55])
        #expect(finished.first?.sets.map(\.target) == [
            .reps(10), .reps(10), .time(seconds: 12), .time(seconds: 12),
        ])
    }

    @Test("""
    A V12 store with a finished workout and one mid-rest opens as it was, no rest skipped; a \
    skip then reopens from the file where it was left, in its hold and after it, its rest's \
    length kept
    """)
    func upgradeMidRestThenSkip() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "StoreUpgrade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "PlusPlus.store")
        try Self.writeV12(at: url)

        let finishedBefore: [WorkoutSession]
        let skipped: WorkoutSession
        let workout: Workout
        do {
            let store = try Self.current(at: url)
            let launch = try await store.launch(weightUnit: .pounds)
            workout = try #require(launch.workout)
            let running = try #require(launch.loggedWorkout)
            finishedBefore = try await store.finishedWorkoutSessions()
            Self.expectAsWritten(running: running, finished: finishedBefore)
            // Mid-rest still: 60 s and the +15 s tap, from the log at 9, not skipped.
            let live = LiveWorkout(workout: workout, loggedWorkout: running)
            let rest = try #require(live.rest())
            #expect(rest.length == 75)
            #expect(rest.startClock == 9)
            #expect(rest.skippedAt == nil)
            #expect(live.situation(at: running.date(ofClock: 30)) == .resting(rest))
            // Skip rest at 44.5, as a tap under today's build stores it.
            skipped = live.skippingRest(at: running.date(ofClock: 44.5))
            try await store.save(skipped)
        }

        // A second launch, on a new container over the same file.
        let store = try Self.current(at: url)
        let reopened = try #require(try await store.launch(weightUnit: .pounds).loggedWorkout)
        #expect(reopened == skipped)
        #expect(reopened.sets.map(\.restAdjustment) == [-56, 15], "The skip cut nothing")
        #expect(reopened.sets.first?.restSkippedAt == nil, "V12's skip stays a cut")
        let tap = try #require(reopened.sets.last?.restSkippedAt)
        #expect(abs(tap - 44.5) < 1e-6)
        let live = LiveWorkout(workout: workout, loggedWorkout: reopened)
        let rest = try #require(live.rest())
        #expect(rest.length == 75)
        #expect(rest.leaveClock == tap + LiveWorkout.skipHold)
        // The plank's "Start in" begins exactly as the rest moves on.
        let count = try #require(reopened.count)
        let lead = Double(LiveWorkout.startIn) + LiveWorkout.startInHold
        #expect(count.startClock == tap + LiveWorkout.skipHold + lead)

        // One answer for where the workout is, from the file as from the screen that skipped.
        let before = LiveWorkout(workout: workout, loggedWorkout: skipped)
        for clock in [tap, tap + 0.1, rest.leaveClock, rest.leaveClock + 3, count.startClock] {
            let now = reopened.date(ofClock: clock)
            #expect(live.situation(at: now) == before.situation(at: now), "At \(clock)")
        }
        #expect(live.situation(at: reopened.date(ofClock: tap + 0.1)) == .resting(rest))
        #expect(live.situation(at: reopened.date(ofClock: rest.leaveClock)) == .countingIn(count))
        // +15 s and a second Skip rest, in the hold and after it, change nothing to store.
        for clock in [tap + 0.1, rest.leaveClock + 0.1] {
            let now = reopened.date(ofClock: clock)
            #expect(live.extendingRest(by: 15, at: now) == reopened)
            #expect(live.skippingRest(at: now) == reopened)
        }
        #expect(try await store.finishedWorkoutSessions() == finishedBefore)
    }
}
