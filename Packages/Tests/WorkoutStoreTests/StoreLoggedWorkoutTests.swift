import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

/// A relaunch is a second store over the same container: it sees only what was saved. Dates are
/// explicit, so nothing rests on how fast the test runs.
@Suite("Store logged workouts")
struct StoreWorkoutSessionTests {
    private let container: ModelContainer

    init() throws {
        container = try WorkoutStoreContainer.make(mode: .inMemory, schema: Store.schema)
    }

    private func relaunch() -> Store {
        Store(modelContainer: container)
    }

    private static func at(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    private static func started(_ workout: Workout, at seconds: TimeInterval) -> WorkoutSession {
        WorkoutSession(workoutID: workout.id, workoutName: workout.name, startedAt: at(seconds))
    }

    @Test(
        "A logged workout in progress comes back with its workout, its time counting the time away",
    )
    func inProgressRelaunch() async throws {
        let workout = Workout(name: "Upper")
        let loggedWorkout = Self.started(workout, at: 10)
        try await relaunch().save(workout, at: Self.at(1))
        try await relaunch().save(loggedWorkout)
        let launch = try await relaunch().launch(weightUnit: .pounds)
        #expect(launch.workout == workout)
        #expect(launch.loggedWorkout == loggedWorkout)
        #expect(launch.loggedWorkout?.elapsed(at: Self.at(100)) == .seconds(90))
    }

    @Test("Pause, resume, and finish round-trip every field")
    func roundTrip() async throws {
        let workout = Workout(name: "Upper")
        try await relaunch().save(workout, at: Self.at(1))
        let paused = Self.started(workout, at: 10).pausing(at: Self.at(20))
        try await relaunch().save(paused)
        #expect(try await relaunch().launch(weightUnit: .pounds).loggedWorkout == paused)
        #expect(paused.elapsed(at: Self.at(1000)) == .seconds(10))
        let resumed = paused.resuming(at: Self.at(50))
        try await relaunch().save(resumed)
        #expect(try await relaunch().launch(weightUnit: .pounds).loggedWorkout == resumed)
        // Paused again and finished while paused: both pauses and the type kept.
        var finished = resumed.pausing(at: Self.at(60)).finishing(at: Self.at(70))
        finished.healthActivity = .flexibility
        try await relaunch().save(finished)
        let stored = try ModelContext(container).fetch(FetchDescriptor<StoredWorkoutSession>())
        #expect(stored.map(\.loggedWorkout) == [finished])
    }

    @Test("Finished logged workouts read back newest finish first, one in progress left out")
    func finishedNewestFirst() async throws {
        let workout = Workout(name: "Upper")
        let older = Self.started(workout, at: 10).finishing(at: Self.at(20))
        let newer = Self.started(workout, at: 30).finishing(at: Self.at(40))
        try await relaunch().save(workout, at: Self.at(1))
        try await relaunch().save(older)
        try await relaunch().save(newer)
        try await relaunch().save(Self.started(workout, at: 50))
        #expect(try await relaunch().finishedWorkoutSessions() == [newer, older])
    }

    @Test("A stored set the app can't read is kept through a save, not deleted")
    func unreadableSetKept() async throws {
        let bench = try WorkoutExercise.builtIn("Barbell bench press")
        let workout = Workout(name: "Upper", exercises: [bench])
        try await relaunch().save(workout, at: Self.at(1))
        let loggedWorkout = Self.started(workout, at: 10)
        try await relaunch().save(loggedWorkout)
        // A set with no row, as a store not written by this build might hold.
        let context = ModelContext(container)
        let stored = try #require(try context.fetch(FetchDescriptor<StoredWorkoutSession>()).first)
        let unreadable = StoredLoggedSet(id: UUID())
        context.insert(unreadable)
        unreadable.workoutSession = stored
        try context.save()
        let loaded = try #require(try await relaunch().launch(weightUnit: .pounds).loggedWorkout)
        #expect(loaded.sets.isEmpty)
        try await relaunch().save(loaded.logging(
            PlannedSet(row: bench.id, round: 1),
            of: bench,
            at: Self.at(20),
        ))
        let sets = try ModelContext(container).fetch(FetchDescriptor<StoredLoggedSet>())
        #expect(sets.contains { $0.id == unreadable.id })
        #expect(sets.count == 2)
    }

    @Test("Logged sets round-trip every field, in the order logged, and a later save diffs them")
    func setsRoundTrip() async throws {
        let superset = UUID()
        var rowing = try WorkoutExercise.builtIn("Dumbbell row") { $0.sets = 2 }
        var plank = try WorkoutExercise.builtIn("Plank") { $0.target = .time(seconds: 45) }
        rowing.supersetID = superset
        plank.supersetID = superset
        let workout = Workout(name: "Upper", exercises: [rowing, plank])
        try await relaunch().save(workout, at: Self.at(1))
        var loggedWorkout = Self.started(workout, at: 10)
        for seconds in [20.0, 30, 40] {
            let next = try #require(workout.nextSet(after: loggedWorkout.sets))
            let row = try #require(workout.exercises.first { $0.id == next.row })
            loggedWorkout = loggedWorkout.logging(next, of: row, at: Self.at(seconds))
        }
        loggedWorkout.sets[0].weight = Weight(47.5, .kilograms)
        try await relaunch().save(loggedWorkout)
        let launched = try #require(try await relaunch().launch(weightUnit: .pounds).loggedWorkout)
        #expect(launched == loggedWorkout)
        #expect(launched.sets.map(\.side) == [.left, .right, nil])
        #expect(launched.sets[2].target == .time(seconds: 45))
        #expect(workout.nextSet(after: launched.sets) == PlannedSet(
            row: rowing.id,
            round: 2,
            side: .left,
        ))

        loggedWorkout.sets.remove(at: 1)
        let finished = loggedWorkout.finishing(at: Self.at(50))
        try await relaunch().save(finished)
        let stored = try ModelContext(container).fetch(FetchDescriptor<StoredWorkoutSession>())
        #expect(stored.map(\.loggedWorkout) == [finished])
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<StoredLoggedSet>()) == 2)
    }

    @Test("Discarding a workout deletes its logged sets")
    func discardDeletesSets() async throws {
        let row = try WorkoutExercise.builtIn("Push-up")
        let workout = Workout(name: "Upper", exercises: [row])
        let store = relaunch()
        try await store.save(workout, at: Self.at(1))
        let loggedWorkout = Self.started(workout, at: 10)
            .logging(PlannedSet(row: row.id, round: 1), of: row, at: Self.at(20))
        try await store.save(loggedWorkout)
        try await store.discardWorkoutSession(loggedWorkout.id)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<StoredLoggedSet>()) == 0)
    }

    @Test("After Discard, launch reopens the workout and the store holds no logged workout")
    func afterDiscard() async throws {
        let workout = Workout(name: "Upper")
        let loggedWorkout = Self.started(workout, at: 10)
        let store = relaunch()
        try await store.save(workout, at: Self.at(1))
        try await store.save(loggedWorkout)
        try await store.discardWorkoutSession(loggedWorkout.id)
        let launch = try await relaunch().launch(weightUnit: .pounds)
        #expect(launch.workout == workout)
        #expect(launch.loggedWorkout == nil)
        #expect(try ModelContext(container).fetch(FetchDescriptor<StoredWorkoutSession>()).isEmpty)
        try await store.discardWorkoutSession(loggedWorkout.id)
    }

    @Test("A logged workout whose workout is gone opens an empty one under its id and name")
    func workoutGone() async throws {
        let workout = Workout(name: "Upper")
        let loggedWorkout = Self.started(workout, at: 10)
        try await relaunch().save(loggedWorkout)
        let launch = try await relaunch().launch(weightUnit: .pounds)
        #expect(launch.workout == Workout(id: workout.id, name: "Upper"))
        #expect(launch.loggedWorkout == loggedWorkout)
    }

    @Test("Of two workouts in progress, the one started later launches")
    func twoInProgress() async throws {
        let earlier = Workout(name: "Earlier")
        let later = Workout(name: "Later")
        let store = relaunch()
        try await store.save(earlier, at: Self.at(1))
        try await store.save(later, at: Self.at(2))
        try await store.save(Self.started(later, at: 20))
        try await store.save(Self.started(earlier, at: 10))
        #expect(try await relaunch().launch(weightUnit: .pounds).workout?.name == "Later")
    }

    @Test("Renaming the workout leaves the name the logged workout stored")
    func renameLeavesWorkoutSession() async throws {
        var workout = Workout(name: "Upper")
        let store = relaunch()
        try await store.save(workout, at: Self.at(1))
        try await store.save(Self.started(workout, at: 10))
        workout.name = "Push"
        try await store.save(workout, at: Self.at(20))
        let launch = try await relaunch().launch(weightUnit: .pounds)
        #expect(launch.workout?.name == "Push")
        #expect(launch.loggedWorkout?.workoutName == "Upper")
    }

    @Test(
        "A workout cleared while in progress is kept until a save without the logged workout",
    )
    func clearedMidLiveWorkout() async throws {
        let workout = try Workout(exercises: [WorkoutExercise(
            exercise: #require(Exercise.builtIn.first),
            weightUnit: .pounds,
        )])
        let loggedWorkout = Self.started(workout, at: 10)
        let store = relaunch()
        try await store.save(workout, at: Self.at(1))
        try await store.save(loggedWorkout)
        let cleared = Workout(id: workout.id)
        try await store.save(cleared, at: Self.at(20), keepsEmpty: true)
        let launch = try await relaunch().launch(weightUnit: .pounds)
        #expect(launch.workout == cleared)
        #expect(launch.loggedWorkout == loggedWorkout)
        try await store.discardWorkoutSession(loggedWorkout.id)
        try await store.save(cleared, at: Self.at(30))
        #expect(try await relaunch().workoutsByRecency(weightUnit: .pounds).isEmpty)
    }

    @Test(
        "Ending a logged workout deletes its workout cleared to nothing in the same write",
        arguments: [false, true],
    )
    func endDeletesCleared(finishes: Bool) async throws {
        let workout = try Workout(exercises: [WorkoutExercise(
            exercise: #require(Exercise.builtIn.first),
            weightUnit: .pounds,
        )])
        let loggedWorkout = Self.started(workout, at: 10)
        let store = relaunch()
        try await store.save(workout, at: Self.at(1))
        try await store.save(loggedWorkout)
        try await store.save(Workout(id: workout.id), at: Self.at(20), keepsEmpty: true)
        if finishes {
            try await store.save(loggedWorkout.finishing(at: Self.at(30)))
        } else {
            try await store.discardWorkoutSession(loggedWorkout.id)
        }
        #expect(try await relaunch().workoutsByRecency(weightUnit: .pounds).isEmpty)
    }

    @Test("Ending a logged workout keeps its workout with exercises")
    func endKeepsWorkout() async throws {
        let workout = Workout(name: "Upper")
        let store = relaunch()
        try await store.save(workout, at: Self.at(1))
        let loggedWorkout = Self.started(workout, at: 10)
        try await store.save(loggedWorkout)
        try await store.discardWorkoutSession(loggedWorkout.id)
        #expect(try await relaunch().workoutsByRecency(weightUnit: .pounds).count == 1)
    }

    #if DEBUG
    @Test("Emptying the store removes workouts too")
    func deleteAll() async throws {
        let workout = Workout(name: "Upper")
        let store = relaunch()
        try await store.save(workout, at: Self.at(1))
        try await store.save(Self.started(workout, at: 10))
        try await store.deleteAll()
        let launch = try await relaunch().launch(weightUnit: .pounds)
        #expect(launch.workout == nil)
        #expect(launch.loggedWorkout == nil)
    }
    #endif
}
