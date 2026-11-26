import Foundation
import SwiftData
import Testing
@testable import Session
@testable import WorkoutStore

/// A timed set's count through the session: each change stored, so a relaunch, a second store
/// on the container, opens on it.
@Suite("Workout session, timed set")
struct AppSessionCountTests {
    private let container: ModelContainer

    init() throws {
        container = try WorkoutStoreContainer.make(mode: .inMemory, schema: Store.schema)
    }

    private func relaunch() -> Store {
        Store(modelContainer: container)
    }

    /// From a count's "Start in" to its set's start: its length and its hold at 0:00.
    private static let lead = Double(LiveWorkout.startIn) + LiveWorkout.startInHold

    private static func at(_ seconds: Double) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    private static func planks() throws -> Workout {
        let exercise = try #require(Exercise.builtIn(id: "plank"))
        var plank = WorkoutExercise(exercise: exercise, weightUnit: .pounds)
        plank.plan.sets = 2
        plank.plan.target = .time(seconds: 30)
        plank.setRest(0)
        return Workout(name: "Core", exercises: [plank])
    }

    @Test(
        "Start on a workout pushed on the Workouts list begins Start in as its screen lands",
        arguments: [SetTarget.time(seconds: 30), .reps(5)],
    )
    func startPushedLandsOnStartIn(target: SetTarget) async throws {
        var workout = try Self.planks()
        workout.exercises[0].plan.target = target
        let store = relaunch()
        try await store.save(workout, at: Self.at(0))
        let session = AppSession(workout: Workout(), store: store, namer: .muscleGroupsOnly)
        session.showWorkouts()
        await session.open(workout.id, weightUnit: .pounds)
        session.start(on: workout.id, at: Self.at(10))
        #expect(session.screen == .pushedWorkout)
        #expect(session.loggedWorkout?.count == nil)
        // Its screen's Start landing on the first set, as at the root.
        session.landOnFirstSet(at: Self.at(10.5))
        let loggedWorkout = try #require(session.loggedWorkout)
        #expect(loggedWorkout.count != nil)
        #expect(loggedWorkout.clock(at: Self.at(10.5 + Self.lead)) == 0)
    }

    @Test("Start, +15 s, and the log are each stored as the session shows them")
    func eachChangeStored() async throws {
        let workout = try Self.planks()
        let row = workout.exercises[0]
        let session = AppSession(workout: workout, store: relaunch(), namer: .muscleGroupsOnly)
        session.save(workout)
        // The set begins after its "Start in" and its 0:00 hold, 6 s after the landing.
        let steps: [(name: String, change: () -> Void)] = [
            ("start", { session.start(on: workout.id, at: Self.at(6)) }),
            ("landed", { session.beginCount(at: Self.at(6)) }),
            ("+15 s", { session.extendCount(by: 15, at: Self.at(20)) }),
            ("log", { session.log(PlannedSet(row: row.id, round: 1), of: row, at: Self.at(30)) }),
        ]
        for step in steps {
            step.change()
            await session.writesLanded()
            let relaunched = try await relaunch().launch(weightUnit: .pounds).loggedWorkout
            #expect(relaunched == session.loggedWorkout, "after \(step.name)")
        }
        let set = try #require(session.loggedWorkout?.sets.first)
        #expect(set.target == .time(seconds: 18))
        #expect(set.timeAdded == 15)
        // The next set's "Start in" waits for the screen to land on it.
        #expect(session.loggedWorkout?.count == nil)
    }

    @Test("+15 s and Skip rest on a rest are each stored; reopened, it moves on as the skip held")
    func restTapsStored() async throws {
        var workout = try Self.planks()
        workout.exercises[0].setRest(30)
        let row = workout.exercises[0]
        let session = AppSession(workout: workout, store: relaunch(), namer: .muscleGroupsOnly)
        session.save(workout)
        // The set begins at 0, after its "Start in" and its hold.
        session.start(on: workout.id, at: Self.at(-Self.lead))
        session.beginCount(at: Self.at(-Self.lead))
        // Logged early at 20 s: its rest runs from 20 to 50.
        session.log(PlannedSet(row: row.id, round: 1), of: row, at: Self.at(20))
        let steps: [(name: String, change: () -> Void)] = [
            ("+15 s", { session.extendRest(by: 15, at: Self.at(25)) }),
            ("skip", { session.skipRest(at: Self.at(30)) }),
        ]
        for step in steps {
            step.change()
            await session.writesLanded()
            let relaunched = try await relaunch().launch(weightUnit: .pounds).loggedWorkout
            #expect(relaunched == session.loggedWorkout, "after \(step.name)")
        }
        let stored = try #require(try await relaunch().launch(weightUnit: .pounds).loggedWorkout)
        let live = LiveWorkout(workout: workout, loggedWorkout: stored)
        let rest = try #require(live.rest())
        // +15 s on the 30 s rest; the skip, stored as its tap, keeps the length.
        #expect(rest.length == 45)
        #expect(rest.skippedAt == stored.clock(at: Self.at(30)))
        // The next plank, with no "Start in" between sets of one exercise, counts from the
        // skip's hold, where the rest moves on.
        let held = 30 + LiveWorkout.skipHold
        #expect(!rest.isOver(atClock: stored.clock(at: Self.at(30))))
        #expect(rest.isOver(atClock: stored.clock(at: Self.at(held))))
        #expect(stored.count?.startClock == stored.clock(at: Self.at(held)))
    }

    @Test("Finish mid-count stores the set at the time done, as Log early would have")
    func finishMidCount() async throws {
        let workout = try Self.planks()
        let session = AppSession(workout: workout, store: relaunch(), namer: .muscleGroupsOnly)
        session.save(workout)
        session.start(on: workout.id, at: Self.at(0))
        session.beginCount(at: Self.at(0))
        let lead = Self.lead
        session.extendCount(by: 15, at: Self.at(lead + 2))
        // Counting from the lead: 18 s done 18 s on.
        session.finish(at: Self.at(lead + 18))
        await session.writesLanded()
        let stored = try ModelContext(container).fetch(FetchDescriptor<StoredWorkout>())
            .map(\.loggedWorkout)
        #expect(stored.first?.sets.map(\.target) == [.time(seconds: 18)])
    }

    @Test("Reopened after the count would have ended, the set is logged at its full time")
    func catchUpAtLaunch() async throws {
        let workout = try Self.planks()
        let first = AppSession(workout: workout, store: relaunch(), namer: .muscleGroupsOnly)
        first.save(workout)
        first.start(on: workout.id, at: Self.at(0))
        first.beginCount(at: Self.at(0))
        await first.writesLanded()

        let stored = try await relaunch().launch(weightUnit: .pounds).loggedWorkout
        let second = AppSession(
            workout: workout,
            loggedWorkout: stored,
            store: relaunch(),
            namer: .muscleGroupsOnly,
        )
        second.catchUp(at: Self.at(300))
        #expect(second.loggedWorkout?.sets.map(\.target) == [.time(seconds: 30)])
        let lead = Self.lead
        #expect(second.loggedWorkout?.sets.first?.clockWhenLogged == lead + 30)
        #expect(second.loggedWorkout?.count?.startClock == 300 + lead)
    }

    @Test("A set's measure flipped twice in a row drops its count at the save, stored")
    func measureFlippedTwice() async throws {
        let workout = try Self.planks()
        let session = AppSession(workout: workout, store: relaunch(), namer: .muscleGroupsOnly)
        session.save(workout)
        session.start(on: workout.id, at: Self.at(0))
        session.beginCount(at: Self.at(0))
        var longer = workout
        longer.exercises[0].plan.target = .time(seconds: 45)
        session.save(longer)
        #expect(session.loggedWorkout?.count != nil, "A time changed keeps the count")
        // Two saves with nothing between, as two edits in one frame: no reaction to either.
        var asReps = longer
        asReps.exercises[0].plan.target = .reps(10)
        session.save(asReps)
        session.save(longer)
        #expect(session.loggedWorkout?.count == nil)
        await session.writesLanded()
        let relaunched = try await relaunch().launch(weightUnit: .pounds).loggedWorkout
        #expect(relaunched?.count == nil)
        session.beginCount(at: Self.at(20))
        #expect(session.loggedWorkout?.count?.startClock == 20 + Self.lead)
    }
}
