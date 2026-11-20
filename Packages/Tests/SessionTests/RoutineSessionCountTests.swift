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
        container = try WorkoutStoreContainer.make(mode: .inMemory, schema: RoutineStore.schema)
    }

    private func relaunch() -> RoutineStore {
        RoutineStore(modelContainer: container)
    }

    private static func at(_ seconds: Double) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    private static func planks() throws -> Routine {
        let exercise = try #require(Exercise.builtIn(id: "plank"))
        var plank = RoutineExercise(exercise: exercise, weightUnit: .pounds)
        plank.plan.sets = 2
        plank.plan.target = .time(seconds: 30)
        plank.setRest(0)
        return Routine(name: "Core", exercises: [plank])
    }

    @Test("Start, Start now, +15 s, and the log are each stored as the session shows them")
    func eachChangeStored() async throws {
        let routine = try Self.planks()
        let row = routine.exercises[0]
        let session = RoutineSession(routine: routine, store: relaunch(), namer: .muscleGroupsOnly)
        session.save(routine)
        let steps: [(name: String, change: () -> Void)] = [
            ("start", { session.start(on: routine.id, at: Self.at(10)) }),
            ("start now", { session.startCountNow(at: Self.at(12)) }),
            ("+15 s", { session.extendCount(by: 15, at: Self.at(20)) }),
            ("log", { session.log(PlannedSet(row: row.id, round: 1), of: row, at: Self.at(30)) }),
        ]
        for step in steps {
            step.change()
            await session.writesLanded()
            let relaunched = try await relaunch().launch(weightUnit: .pounds).workout
            #expect(relaunched == session.workout, "after \(step.name)")
        }
        let set = try #require(session.workout?.sets.first)
        #expect(set.target == .time(seconds: 18))
        #expect(set.timeAdded == 15)
        // The next set waits on "Starts in" from the log.
        #expect(session.workout?.count?.startClock == 30)
    }

    @Test("Reopened after the count would have ended, the set is logged at its full time")
    func catchUpAtLaunch() async throws {
        let routine = try Self.planks()
        let first = RoutineSession(routine: routine, store: relaunch(), namer: .muscleGroupsOnly)
        first.save(routine)
        first.start(on: routine.id, at: Self.at(0))
        await first.writesLanded()

        let stored = try await relaunch().launch(weightUnit: .pounds).workout
        let second = RoutineSession(
            routine: routine,
            workout: stored,
            store: relaunch(),
            namer: .muscleGroupsOnly,
        )
        second.catchUp(at: Self.at(300))
        #expect(second.workout?.sets.map(\.target) == [.time(seconds: 30)])
        #expect(second.workout?.sets.first?.clockWhenLogged == 40)
        #expect(second.workout?.count?.startClock == 310)
    }
}
