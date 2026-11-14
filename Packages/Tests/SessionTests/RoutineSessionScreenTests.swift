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
    private let other = Routine(name: "Legs")

    init() async throws {
        let container = try WorkoutStoreContainer.make(
            mode: .inMemory,
            schema: RoutineStore.schema,
        )
        store = RoutineStore(modelContainer: container)
        try await store.save(saved, at: Date(timeIntervalSinceReferenceDate: 1))
        try await store.save(other, at: Date(timeIntervalSinceReferenceDate: 2))
    }

    private func session(_ routine: Routine = Routine(name: "Upper")) -> RoutineSession {
        RoutineSession(routine: routine, store: store, namer: .muscleGroupsOnly)
    }

    /// A session on the Routines screen, `saved` pushed on it.
    private func pushedSession() async -> RoutineSession {
        let session = session()
        session.showRoutines()
        await session.open(saved.id, weightUnit: .pounds, pushed: true)
        return session
    }

    @Test("A session opens on the routine at the root")
    func opensAtRoot() {
        let session = session()
        #expect(session.screen == .routine)
        #expect(!session.isRoutinePushed)
        #expect(session.showing == .routine)
    }

    @Test("Routines from the drawer shows the list, marked, and closes the drawer")
    func showRoutines() {
        let session = session()
        session.isDrawerOpen = true
        session.showRoutines()
        #expect(session.screen == .routines)
        #expect(!session.isRoutinePushed)
        #expect(session.showing == .routines)
        #expect(!session.isDrawerOpen)
    }

    @Test("A routine opened from the list is pushed on it")
    func openFromList() async {
        let session = await pushedSession()
        #expect(session.screen == .pushedRoutine)
        #expect(session.isRoutinePushed)
        #expect(session.current == saved)
        #expect(session.showing == .routine)
    }

    @Test("The open routine opened from the list is pushed on it as it is")
    func openOpenFromList() async {
        let session = session()
        session.showRoutines()
        await session.open(session.current.id, weightUnit: .pounds, pushed: true)
        #expect(session.screen == .pushedRoutine)
        #expect(session.current.name == "Upper")
    }

    @Test("The list's + pushes a new routine on it, marked new")
    func newFromList() async {
        let session = session()
        session.showRoutines()
        await session.startNew(pushed: true)
        #expect(session.screen == .pushedRoutine)
        #expect(session.current.isEmpty)
        #expect(session.showing == .new)
    }

    @Test("Back from a pushed routine shows the list again")
    func back() async {
        let session = await pushedSession()
        session.isRoutinePushed = false
        #expect(session.screen == .routines)
        #expect(session.showing == .routines)
        #expect(session.current == saved)
    }

    @Test("A push asked for at the root leaves the routine at the root")
    func noPushAtRoot() {
        let session = session()
        session.isRoutinePushed = true
        #expect(session.screen == .routine)
        #expect(!session.isRoutinePushed)
    }

    @Test("A push asked for again over a pushed routine keeps it pushed")
    func pushOverPushed() async {
        let session = await pushedSession()
        session.isRoutinePushed = true
        #expect(session.screen == .pushedRoutine)
    }

    @Test("A routine opened from the drawer over a pushed one shows at the root")
    func openFromDrawerOverPushed() async {
        let session = await pushedSession()
        session.isDrawerOpen = true
        await session.open(other.id, weightUnit: .pounds)
        #expect(session.screen == .routine)
        #expect(session.current == other)
        #expect(!session.isDrawerOpen)
    }

    @Test("New from the drawer over a pushed routine shows at the root, marked new")
    func newFromDrawerOverPushed() async {
        let session = await pushedSession()
        await session.startNew()
        #expect(session.screen == .routine)
        #expect(session.current.isEmpty)
        #expect(session.showing == .new)
    }

    @Test("Routines from the drawer over a pushed routine shows the list")
    func routinesOverPushed() async {
        let session = await pushedSession()
        session.showRoutines()
        #expect(session.screen == .routines)
        #expect(session.showing == .routines)
    }

    @Test("Start on a pushed routine shows its workout at the root, as the routine is now")
    func startPushed() async throws {
        let session = await pushedSession()
        let exercise = try #require(Exercise.builtIn(id: "barbell-bench-press"))
        var edited = saved
        edited.exercises = [RoutineExercise(exercise: exercise, weightUnit: .pounds)]
        session.save(edited)
        session.start()
        #expect(session.screen == .routine)
        #expect(!session.isRoutinePushed)
        #expect(session.opened == edited)
        #expect(session.workout?.routineID == saved.id)
    }

    @Test("Start at the root keeps the screen the routine opened with")
    func startAtRoot() throws {
        let routine = Routine(name: "Upper")
        let session = session(routine)
        let exercise = try #require(Exercise.builtIn(id: "barbell-bench-press"))
        var edited = routine
        edited.exercises = [RoutineExercise(exercise: exercise, weightUnit: .pounds)]
        session.save(edited)
        session.start()
        #expect(session.screen == .routine)
        #expect(session.opened == routine)
    }

    @Test("A workout relaunched opens on its routine at the root")
    func relaunchMidWorkout() {
        let routine = Routine(name: "Upper")
        let workout = Workout(routineID: routine.id, routineName: "Upper", startedAt: .now)
        let session = RoutineSession(
            routine: routine,
            workout: workout,
            store: store,
            namer: .muscleGroupsOnly,
        )
        #expect(session.screen == .routine)
        #expect(session.isDrawerLocked)
    }
}
