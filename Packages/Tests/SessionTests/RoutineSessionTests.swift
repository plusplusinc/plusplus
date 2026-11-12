import Foundation
import SwiftData
import Testing
@testable import Session
@testable import WorkoutStore

/// The order the session sends its writes in. A relaunch is a second store over the same
/// container: it sees only what landed.
@Suite("Routine session")
struct RoutineSessionTests {
    private let container: ModelContainer

    init() throws {
        container = try WorkoutStoreContainer.make(mode: .inMemory, schema: RoutineStore.schema)
    }

    private func relaunch() -> RoutineStore {
        RoutineStore(modelContainer: container)
    }

    private func session(_ routine: Routine = Routine()) -> RoutineSession {
        RoutineSession(routine: routine, store: relaunch())
    }

    private static func upper() throws -> Routine {
        let bench = try RoutineExercise.builtIn("Barbell bench press")
        return Routine(name: "Upper", exercises: [bench])
    }

    @Test("An edit just before a switch is saved before the next routine opens")
    func editBeforeSwitch() async throws {
        let session = session()
        let routine = try Self.upper()
        session.save(routine)
        await session.startNew()
        #expect(session.current.isEmpty)
        #expect(try await relaunch().launch(weightUnit: .pounds).routine == routine)
    }

    @Test("An edit just before opening another routine is saved")
    func editBeforeOpen() async throws {
        let other = Routine(name: "Lower")
        try await relaunch().save(other, at: Date(timeIntervalSinceReferenceDate: 1))
        let session = session()
        let routine = try Self.upper()
        session.save(routine)
        await session.open(other.id, weightUnit: .pounds)
        #expect(session.current == other)
        #expect(try await relaunch().openRoutine(routine.id, weightUnit: .pounds) == routine)
    }

    @Test("Of edits not yet saved, the newest is the one that lands")
    func newestLands() async throws {
        let session = session()
        var routine = try Self.upper()
        for name in ["One", "Two", "Three"] {
            routine.name = name
            session.save(routine)
        }
        await session.startNew()
        #expect(try await relaunch().openRoutine(routine.id, weightUnit: .pounds)?.name == "Three")
    }

    @Test("A workout's end is saved even with the next start queued behind it")
    func endBeforeNextStart() async throws {
        let session = try session(Self.upper())
        session.start(routineName: "Upper", at: Date(timeIntervalSinceReferenceDate: 10))
        let first = try #require(session.workout)
        await session.writesLanded()
        session.finish(routineName: "Upper", at: Date(timeIntervalSinceReferenceDate: 20))
        session.start(routineName: "Upper", at: Date(timeIntervalSinceReferenceDate: 30))
        let second = try #require(session.workout)
        await session.writesLanded()
        let stored = try ModelContext(container).fetch(FetchDescriptor<StoredWorkout>())
            .map(\.workout)
        #expect(stored.first { $0.id == first.id }?
            .endedAt == Date(timeIntervalSinceReferenceDate: 20))
        #expect(stored.first { $0.id == second.id }?.isInProgress == true)
    }

    @Test("A routine emptied during a workout is kept until the workout ends, then deleted")
    func emptiedDuringWorkout() async throws {
        let routine = try Self.upper()
        let session = session(routine)
        session.save(routine)
        session.start(routineName: "Upper")
        session.save(Routine(id: routine.id))
        await session.writesLanded()
        let kept = try await relaunch().openRoutine(routine.id, weightUnit: .pounds)
        #expect(kept?.isEmpty == true)
        session.finish(routineName: "Upper")
        await session.writesLanded()
        #expect(try await relaunch().openRoutine(routine.id, weightUnit: .pounds) == nil)
    }

    @Test("Logging through the session stores the set at the row's numbers")
    func logStores() async throws {
        let routine = try Self.upper()
        let row = routine.exercises[0]
        let session = session(routine)
        session.save(routine)
        session.start(routineName: "Upper")
        let set = PlannedSet(row: row.id, round: 1)
        session.log(set, of: row)
        await session.writesLanded()
        let stored = try #require(try await relaunch().launch(weightUnit: .pounds).workout)
        #expect(stored.sets.map(\.planned) == [set])
        #expect(stored.sets.first?.target == row.plan.target)
        #expect(stored.sets.first?.weight == row.shownWeight)
    }
}

extension RoutineExercise {
    /// A row of the built-in exercise named `name`, its default plan changed by `edit`.
    static func builtIn(
        _ name: String,
        _ edit: (inout ExercisePlan) -> Void = { _ in },
    ) throws -> RoutineExercise {
        let exercise = try #require(Exercise.builtIn.first { $0.name == name })
        var plan = exercise.defaultPlan(in: .pounds)
        edit(&plan)
        return RoutineExercise(exercise: exercise, plan: plan)
    }
}
