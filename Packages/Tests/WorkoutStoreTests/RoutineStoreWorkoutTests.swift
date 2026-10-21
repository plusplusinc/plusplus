import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

/// A relaunch is a second store over the same container: it sees only what was saved. Dates are
/// explicit, so nothing rests on how fast the test runs.
@Suite("Routine store workouts")
struct RoutineStoreWorkoutTests {
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

    private static func started(_ routine: Routine, at seconds: TimeInterval) -> Workout {
        Workout(routineID: routine.id, routineName: routine.name, startedAt: at(seconds))
    }

    @Test("A workout in progress comes back with its routine, its time counting the time away")
    func inProgressRelaunch() async throws {
        let routine = Routine(name: "Upper")
        let workout = Self.started(routine, at: 10)
        try await relaunch().save(routine, at: Self.at(1))
        try await relaunch().save(workout)
        let launch = try await relaunch().launch(weightUnit: .pounds)
        #expect(launch.routine == routine)
        #expect(launch.workout == workout)
        #expect(launch.workout?.elapsed(at: Self.at(100)) == .seconds(90))
    }

    @Test("Pause, resume, and finish round-trip every field")
    func roundTrip() async throws {
        let routine = Routine(name: "Upper")
        try await relaunch().save(routine, at: Self.at(1))
        let paused = Self.started(routine, at: 10).pausing(at: Self.at(20))
        try await relaunch().save(paused)
        #expect(try await relaunch().launch(weightUnit: .pounds).workout == paused)
        #expect(paused.elapsed(at: Self.at(1000)) == .seconds(10))
        let resumed = paused.resuming(at: Self.at(50))
        try await relaunch().save(resumed)
        #expect(try await relaunch().launch(weightUnit: .pounds).workout == resumed)
        let store = relaunch()
        try await store.save(resumed.finishing(at: Self.at(70)))
        let stored = try ModelContext(container).fetch(FetchDescriptor<StoredWorkout>())
        #expect(stored.map(\.workout) == [resumed.finishing(at: Self.at(70))])
    }

    @Test("After Finish, launch opens a new routine, until a routine is opened or edited")
    func afterFinish() async throws {
        var routine = Routine(name: "Upper")
        let store = relaunch()
        try await store.save(routine, at: Self.at(1))
        try await store.save(Self.started(routine, at: 10).finishing(at: Self.at(20)))
        let launch = try await relaunch().launch(weightUnit: .pounds)
        #expect(launch.routine == nil)
        #expect(launch.workout == nil)
        _ = try await store.openRoutine(routine.id, weightUnit: .pounds, at: Self.at(30))
        #expect(try await relaunch().launch(weightUnit: .pounds).routine == routine)
        try await store.save(Self.started(routine, at: 40).finishing(at: Self.at(50)))
        #expect(try await relaunch().launch(weightUnit: .pounds).routine == nil)
        routine.name = "Upper again"
        try await store.save(routine, at: Self.at(60))
        #expect(try await relaunch().launch(weightUnit: .pounds).routine == routine)
    }

    @Test("After Discard, launch reopens the routine and the store holds no workout")
    func afterDiscard() async throws {
        let routine = Routine(name: "Upper")
        let workout = Self.started(routine, at: 10)
        let store = relaunch()
        try await store.save(routine, at: Self.at(1))
        try await store.save(workout)
        try await store.discardWorkout(workout.id)
        let launch = try await relaunch().launch(weightUnit: .pounds)
        #expect(launch.routine == routine)
        #expect(launch.workout == nil)
        #expect(try ModelContext(container).fetch(FetchDescriptor<StoredWorkout>()).isEmpty)
        try await store.discardWorkout(workout.id)
    }

    @Test("A workout whose routine is gone opens an empty one under its id and name")
    func routineGone() async throws {
        let routine = Routine(name: "Upper")
        let workout = Self.started(routine, at: 10)
        try await relaunch().save(workout)
        let launch = try await relaunch().launch(weightUnit: .pounds)
        #expect(launch.routine == Routine(id: routine.id, name: "Upper"))
        #expect(launch.workout == workout)
    }

    @Test("Of two workouts in progress, the one started later launches")
    func twoInProgress() async throws {
        let earlier = Routine(name: "Earlier")
        let later = Routine(name: "Later")
        let store = relaunch()
        try await store.save(earlier, at: Self.at(1))
        try await store.save(later, at: Self.at(2))
        try await store.save(Self.started(later, at: 20))
        try await store.save(Self.started(earlier, at: 10))
        #expect(try await relaunch().launch(weightUnit: .pounds).routine?.name == "Later")
    }

    @Test("Renaming the routine leaves the name the workout stored")
    func renameLeavesWorkout() async throws {
        var routine = Routine(name: "Upper")
        let store = relaunch()
        try await store.save(routine, at: Self.at(1))
        try await store.save(Self.started(routine, at: 10))
        routine.name = "Push"
        try await store.save(routine, at: Self.at(20))
        let launch = try await relaunch().launch(weightUnit: .pounds)
        #expect(launch.routine?.name == "Push")
        #expect(launch.workout?.routineName == "Upper")
    }

    @Test(
        "A routine cleared while its workout runs is kept until a save without the workout",
    )
    func clearedMidWorkout() async throws {
        let routine = try Routine(exercises: [RoutineExercise(
            exercise: #require(Exercise.builtIn.first),
            weightUnit: .pounds,
        )])
        let workout = Self.started(routine, at: 10)
        let store = relaunch()
        try await store.save(routine, at: Self.at(1))
        try await store.save(workout)
        let cleared = Routine(id: routine.id)
        try await store.save(cleared, at: Self.at(20), keepsEmpty: true)
        let launch = try await relaunch().launch(weightUnit: .pounds)
        #expect(launch.routine == cleared)
        #expect(launch.workout == workout)
        try await store.discardWorkout(workout.id)
        try await store.save(cleared, at: Self.at(30))
        #expect(try await relaunch().routinesByRecency(weightUnit: .pounds).routines.isEmpty)
    }

    #if DEBUG
    @Test("Emptying the store removes workouts too")
    func deleteAll() async throws {
        let routine = Routine(name: "Upper")
        let store = relaunch()
        try await store.save(routine, at: Self.at(1))
        try await store.save(Self.started(routine, at: 10))
        try await store.deleteAll()
        let launch = try await relaunch().launch(weightUnit: .pounds)
        #expect(launch.routine == nil)
        #expect(launch.workout == nil)
    }
    #endif
}
