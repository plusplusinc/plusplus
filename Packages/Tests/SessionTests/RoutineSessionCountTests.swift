import Foundation
import SwiftData
import Testing
@testable import Session
@testable import WorkoutStore

/// A timed set's count through the session: each change stored, so a relaunch, a second store
/// on the container, opens on it.
@Suite("Routine session, timed set")
struct RoutineSessionCountTests {
    private let container: ModelContainer

    init() throws {
        container = try WorkoutStoreContainer.make(mode: .inMemory, schema: Store.schema)
    }

    private func relaunch() -> Store {
        Store(modelContainer: container)
    }

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

    @Test("Start, Start now, +15 s, and the log are each stored as the session shows them")
    func eachChangeStored() async throws {
        let routine = try Self.planks()
        let row = routine.exercises[0]
        let session = RoutineSession(routine: routine, store: relaunch(), namer: .muscleGroupsOnly)
        session.save(routine)
        let steps: [(name: String, change: () -> Void)] = [
            ("start", { session.start(on: routine.id, at: Self.at(10)) }),
            ("landed", { session.beginCount(at: Self.at(10)) }),
            ("start now", { session.startCountNow(at: Self.at(12)) }),
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
        // The next set's "Starts in" waits for the screen to land on it.
        #expect(session.loggedWorkout?.count == nil)
    }

    @Test("+15 s and Skip rest on the rest after a set are each stored; reopened, the rest is over")
    func restTapsStored() async throws {
        var routine = try Self.planks()
        routine.exercises[0].setRest(30)
        let row = routine.exercises[0]
        let session = RoutineSession(routine: routine, store: relaunch(), namer: .muscleGroupsOnly)
        session.save(routine)
        session.start(on: routine.id, at: Self.at(0))
        session.beginCount(at: Self.at(0))
        session.startCountNow(at: Self.at(0))
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
        let live = LiveWorkout(routine: routine, loggedWorkout: stored)
        let rest = try #require(live.rest())
        #expect(rest.length == 10)
        #expect(rest.isOver(atClock: stored.clock(at: Self.at(30))))
        // The next plank counts from the skip.
        #expect(stored.count?.startClock == 30)
    }

    @Test("Finish mid-count stores the set at the time done, as Log early would have")
    func finishMidCount() async throws {
        let routine = try Self.planks()
        let session = RoutineSession(routine: routine, store: relaunch(), namer: .muscleGroupsOnly)
        session.save(routine)
        session.start(on: routine.id, at: Self.at(0))
        session.beginCount(at: Self.at(0))
        session.extendCount(by: 15, at: Self.at(12))
        // Counting from 10: 18 s done at 28.
        session.finish(at: Self.at(28))
        await session.writesLanded()
        let stored = try ModelContext(container).fetch(FetchDescriptor<StoredWorkout>())
            .map(\.loggedWorkout)
        #expect(stored.first?.sets.map(\.target) == [.time(seconds: 18)])
    }

    @Test("Reopened after the count would have ended, the set is logged at its full time")
    func catchUpAtLaunch() async throws {
        let routine = try Self.planks()
        let first = RoutineSession(routine: routine, store: relaunch(), namer: .muscleGroupsOnly)
        first.save(routine)
        first.start(on: routine.id, at: Self.at(0))
        first.beginCount(at: Self.at(0))
        await first.writesLanded()

        let stored = try await relaunch().launch(weightUnit: .pounds).loggedWorkout
        let second = RoutineSession(
            routine: routine,
            loggedWorkout: stored,
            store: relaunch(),
            namer: .muscleGroupsOnly,
        )
        second.catchUp(at: Self.at(300))
        #expect(second.loggedWorkout?.sets.map(\.target) == [.time(seconds: 30)])
        #expect(second.loggedWorkout?.sets.first?.clockWhenLogged == 40)
        #expect(second.loggedWorkout?.count?.startClock == 310)
    }
}
