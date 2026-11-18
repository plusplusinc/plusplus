import Foundation
import SwiftData
import Testing
@testable import Session
@testable import WorkoutStore

/// Where the session shows, one value: the routine, the Routines screen, or a routine pushed on
/// it, through each way in and out, and what the drawer marks for each.
@Suite("Routine session screen")
struct RoutineSessionScreenTests {
    private let store: RoutineStore
    private let saved = Routine(name: "Lower")

    init() async throws {
        let container = try WorkoutStoreContainer.make(
            mode: .inMemory,
            schema: RoutineStore.schema,
        )
        store = RoutineStore(modelContainer: container)
        try await store.save(saved, at: Date(timeIntervalSinceReferenceDate: 1))
    }

    private func session(_ routine: Routine = Routine(name: "Upper")) -> RoutineSession {
        RoutineSession(routine: routine, store: store, namer: .muscleGroupsOnly)
    }

    /// A session on the Routines screen, `saved` pushed on it.
    private func pushedSession() async -> RoutineSession {
        let session = session()
        session.showRoutines()
        await session.open(saved.id, weightUnit: .pounds)
        return session
    }

    /// `routine` with a bench press added, saved to the session.
    private func addingExercise(to routine: Routine, in session: RoutineSession) throws -> Routine {
        let exercise = try #require(Exercise.builtIn(id: "barbell-bench-press"))
        var edited = routine
        edited.exercises = [RoutineExercise(exercise: exercise, weightUnit: .pounds)]
        session.save(edited)
        return edited
    }

    @Test("Routines from the drawer shows the list, marked, and closes the drawer")
    func showRoutines() {
        let session = session()
        session.openDrawer()
        session.showRoutines()
        #expect(session.screen == .routines)
        #expect(session.showing == .routines)
        #expect(!session.isDrawerOpen)
    }

    @Test("A routine opened from the list is pushed on it")
    func openFromList() async {
        let session = await pushedSession()
        #expect(session.screen == .pushedRoutine)
        #expect(session.current == saved)
        #expect(session.showing == .routine)
    }

    @Test("The open routine opened from the list is pushed on it as it is")
    func openOpenFromList() async {
        let session = session()
        session.showRoutines()
        await session.open(session.current.id, weightUnit: .pounds)
        #expect(session.screen == .pushedRoutine)
        #expect(session.current.name == "Upper")
    }

    @Test("The list's + pushes a new routine on it, which marks neither place")
    func newFromList() async {
        let session = session()
        session.showRoutines()
        await session.startNew()
        #expect(session.screen == .pushedRoutine)
        #expect(session.current.isEmpty)
        #expect(session.showing == .routine)
    }

    @Test("Back from a pushed routine shows the list again")
    func back() async {
        let session = await pushedSession()
        session.popRoutine()
        #expect(session.screen == .routines)
        #expect(session.showing == .routines)
        #expect(session.current == saved)
    }

    @Test("A pop the stack sends after Start leaves the workout at the root")
    func popAfterStart() async throws {
        let session = await pushedSession()
        let routine = try addingExercise(to: session.current, in: session)
        session.start(on: routine.id)
        session.popRoutine()
        #expect(session.screen == .routine)
    }

    @Test("Start on a pushed routine shows its workout at the root, as the routine is now")
    func startPushed() async throws {
        let session = await pushedSession()
        let edited = try addingExercise(to: saved, in: session)
        session.start(on: session.current.id)
        #expect(session.screen == .routine)
        #expect(session.opened == edited)
        #expect(session.workout?.routineID == saved.id)
    }

    @Test("Start at the root keeps the screen the routine opened with")
    func startAtRoot() throws {
        let routine = Routine(name: "Upper")
        let session = session(routine)
        _ = try addingExercise(to: routine, in: session)
        session.start(on: session.current.id)
        #expect(session.screen == .routine)
        #expect(session.opened == routine)
    }
}
