import Foundation
import SwiftData
import Testing
@testable import Session
@testable import WorkoutStore

/// Where the session shows, one value: the routine, the Routines screen, or a routine pushed on
/// it, through each way in and out, and what the drawer marks for each.
@Suite("Routine session screen")
struct AppSessionScreenTests {
    private let store: Store
    private let saved = Workout(name: "Lower")

    init() async throws {
        let container = try WorkoutStoreContainer.make(
            mode: .inMemory,
            schema: Store.schema,
        )
        store = Store(modelContainer: container)
        try await store.save(saved, at: Date(timeIntervalSinceReferenceDate: 1))
    }

    private func session(_ workout: Workout = Workout(name: "Upper")) -> AppSession {
        AppSession(workout: workout, store: store, namer: .muscleGroupsOnly)
    }

    /// A session on a routine of one bench press row, and the row, whose sheet can open.
    private func sessionWithRow() throws -> (AppSession, row: WorkoutExercise.ID) {
        let exercise = try #require(Exercise.builtIn(id: "barbell-bench-press"))
        let row = WorkoutExercise(exercise: exercise, weightUnit: .pounds)
        return (session(Workout(name: "Upper", exercises: [row])), row.id)
    }

    /// A session on the Routines screen, `saved` pushed on it.
    private func pushedSession() async -> AppSession {
        let session = session()
        session.showWorkouts()
        await session.open(saved.id, weightUnit: .pounds)
        return session
    }

    /// `routine` with a bench press added, saved to the session.
    private func addingExercise(to workout: Workout, in session: AppSession) throws -> Workout {
        let exercise = try #require(Exercise.builtIn(id: "barbell-bench-press"))
        var edited = workout
        edited.exercises = [WorkoutExercise(exercise: exercise, weightUnit: .pounds)]
        session.save(edited)
        return edited
    }

    @Test("Routines from the drawer shows the list, marked, and closes the drawer")
    func showWorkouts() {
        let session = session()
        session.openDrawer()
        session.showWorkouts()
        #expect(session.screen == .workouts)
        #expect(session.showing == .workouts)
        #expect(!session.isDrawerOpen)
    }

    @Test("The drawer and a row's sheet keep each other out, whichever was asked for first")
    func drawerAndRowSheetExclude() throws {
        let (session, row) = try sessionWithRow()
        // A ++ after a sheet is asked for, before it rises over ++, as after Create.
        session.openRowSheet(RowSheet(id: row, opensCustomizing: true))
        session.openDrawer()
        #expect(!session.isDrawerOpen)
        #expect(session.rowSheet?.id == row)
        session.closeRowSheet()
        session.openDrawer()
        #expect(session.isDrawerOpen)
        // A created row's sheet due after ++ opened the drawer.
        session.openRowSheet(RowSheet(id: row, opensCustomizing: true))
        #expect(session.rowSheet == nil)
    }

    @Test("A swipe under way keeps a row's sheet out, and the drawer still opens as it ends")
    func heldDrawerKeepsRowSheetOut() throws {
        let (session, row) = try sessionWithRow()
        session.holdDrawer(true)
        session.openRowSheet(RowSheet(id: row, opensCustomizing: true))
        #expect(session.rowSheet == nil)
        session.holdDrawer(false)
        session.openDrawer()
        #expect(session.isDrawerOpen)
    }

    @Test("A created row's sheet waited for opens once the hold has passed")
    func rowSheetAfterHold() async throws {
        let (session, row) = try sessionWithRow()
        await session.openRowSheet(RowSheet(id: row), after: .milliseconds(10)) { true }
        #expect(session.rowSheet?.id == row)
    }

    @Test("A row's sheet opened again after closing is a new opening; the same ask keeps its own")
    func eachOpeningIsItsOwn() throws {
        let (session, row) = try sessionWithRow()
        session.openRowSheet(RowSheet(id: row))
        let first = try #require(session.rowSheet).opening
        // A double tap, the sheet still rising.
        session.openRowSheet(RowSheet(id: row))
        #expect(session.rowSheet?.opening == first)
        session.closeRowSheet()
        session.openRowSheet(RowSheet(id: row))
        let second = try #require(session.rowSheet).opening
        #expect(second != first, "The sheet opened again would keep the last one's state")
    }

    @Test("A row the open routine no longer has opens no sheet, as when tapped as it leaves")
    func goneRowOpensNoSheet() throws {
        let (session, row) = try sessionWithRow()
        session.save(Workout(id: session.current.id, name: "Upper"))
        session.openRowSheet(RowSheet(id: row))
        #expect(session.rowSheet == nil)
        session.openDrawer()
        #expect(session.isDrawerOpen, "The gone row's sheet kept the drawer shut")
    }

    @Test("A wait cancelled as its screen goes sets nothing")
    func cancelledWaitSetsNothing() async throws {
        let (session, row) = try sessionWithRow()
        let wait = Task {
            await session.openRowSheet(RowSheet(id: row), after: .seconds(60)) { true }
        }
        wait.cancel()
        await wait.value
        #expect(session.rowSheet == nil)
        session.openDrawer()
        #expect(session.isDrawerOpen)
    }

    @Test("A wait outlived by a pop off the Routines screen sets nothing")
    func poppedWaitSetsNothing() async throws {
        let session = await pushedSession()
        let row = try #require(addingExercise(to: saved, in: session).exercises.first).id
        // The pushed screen goes only once its pop has played, after the pop itself; the pop
        // lands at the hold's end, as the wait's own conditions are read.
        await session.openRowSheet(RowSheet(id: row), after: .milliseconds(10)) {
            session.popWorkout()
            return true
        }
        #expect(session.rowSheet == nil)
        session.openDrawer()
        #expect(session.isDrawerOpen)
    }

    @Test("A routine opened from the list is pushed on it")
    func openFromList() async {
        let session = await pushedSession()
        #expect(session.screen == .pushedWorkout)
        #expect(session.current == saved)
        #expect(session.showing == .workout)
    }

    @Test("The open routine opened from the list is pushed on it as it is")
    func openOpenFromList() async {
        let session = session()
        session.showWorkouts()
        await session.open(session.current.id, weightUnit: .pounds)
        #expect(session.screen == .pushedWorkout)
        #expect(session.current.name == "Upper")
    }

    @Test("The list's + pushes a new routine on it, which marks neither place")
    func newFromList() async {
        let session = session()
        session.showWorkouts()
        await session.startNew()
        #expect(session.screen == .pushedWorkout)
        #expect(session.current.isEmpty)
        #expect(session.showing == .workout)
    }

    @Test("Back from a pushed routine shows the list again")
    func back() async {
        let session = await pushedSession()
        session.popWorkout()
        #expect(session.screen == .workouts)
        #expect(session.showing == .workouts)
        #expect(session.current == saved)
    }

    @Test("A pop the stack sends after Start leaves the workout at the root")
    func popAfterStart() async throws {
        let session = await pushedSession()
        let workout = try addingExercise(to: session.current, in: session)
        session.start(on: workout.id)
        session.popWorkout()
        #expect(session.screen == .workout)
    }

    @Test("Start on a pushed routine shows its workout at the root, as the routine is now")
    func startPushed() async throws {
        let session = await pushedSession()
        let edited = try addingExercise(to: saved, in: session)
        session.start(on: session.current.id)
        #expect(session.screen == .workout)
        #expect(session.opened == edited)
        #expect(session.loggedWorkout?.workoutID == saved.id)
    }

    @Test("Start at the root keeps the screen the routine opened with")
    func startAtRoot() throws {
        let workout = Workout(name: "Upper")
        let session = session(workout)
        _ = try addingExercise(to: workout, in: session)
        session.start(on: session.current.id)
        #expect(session.screen == .workout)
        #expect(session.opened == workout)
    }
}
