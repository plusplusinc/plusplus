import Foundation
import SwiftData
import Testing
@testable import Session
@testable import WorkoutStore

/// Where the session shows, one value: the workout, the Workouts screen, or a workout pushed on
/// it, through each way in and out, and what the drawer marks for each.
@Suite("Workout session screen")
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

    /// A session on a workout of one bench press row, and the row, whose sheet can open.
    private func sessionWithRow() throws -> (AppSession, row: WorkoutExercise.ID) {
        let exercise = try #require(Exercise.builtIn(id: "barbell-bench-press"))
        let row = WorkoutExercise(exercise: exercise, weightUnit: .pounds)
        return (session(Workout(name: "Upper", exercises: [row])), row.id)
    }

    /// A session on the Workouts screen, `saved` pushed on it.
    private func pushedSession() async -> AppSession {
        let session = session()
        session.showWorkouts()
        await session.open(saved.id, weightUnit: .pounds)
        return session
    }

    /// `workout` with a bench press added, saved to the session.
    private func addingExercise(to workout: Workout, in session: AppSession) throws -> Workout {
        let exercise = try #require(Exercise.builtIn(id: "barbell-bench-press"))
        var edited = workout
        edited.exercises = [WorkoutExercise(exercise: exercise, weightUnit: .pounds)]
        session.save(edited)
        return edited
    }

    @Test("Workouts from the drawer shows the list, marked, and closes the drawer")
    func showWorkouts() {
        let session = session()
        session.openDrawer()
        session.showWorkouts()
        #expect(session.screen == .workouts)
        #expect(session.showing == .workouts)
        #expect(!session.isDrawerOpen)
    }

    @Test("Log from the drawer shows Log, marked, and closes the drawer")
    func showLog() {
        let session = session()
        session.openDrawer()
        session.showLog()
        #expect(session.screen == .log)
        #expect(session.showing == .log)
        #expect(!session.isDrawerOpen)
    }

    @Test("A logged workout opened from History is pushed on Log, still marking Log; back pops it")
    func openLoggedWorkout() {
        let session = session()
        session.showLog()
        let id = UUID()
        session.openLoggedWorkout(id)
        #expect(session.screen == .loggedWorkout(id))
        #expect(session.screen.isPushed)
        #expect(session.showing == .log)
        session.popLoggedWorkout()
        #expect(session.screen == .log)
        // A pop sent once the place has changed leaves it.
        session.showWorkouts()
        session.popLoggedWorkout()
        #expect(session.screen == .workouts)
    }

    @Test("Log reads the finished logged workouts, leaving one in progress out")
    func refreshLog() async throws {
        let finished = LoggedWorkout(
            workoutID: saved.id,
            workoutName: saved.name,
            startedAt: Date(timeIntervalSinceReferenceDate: 10),
        ).finishing(at: Date(timeIntervalSinceReferenceDate: 70))
        try await store.save(finished)
        try await store.save(LoggedWorkout(
            workoutID: saved.id,
            workoutName: saved.name,
            startedAt: Date(timeIntervalSinceReferenceDate: 100),
        ))
        let session = session()
        #expect(session.log == nil)
        await session.refreshLog()
        #expect(session.log?.loggedWorkouts == [finished])
    }

    @Test("Finish names the workout for Log to bring in, and a read straight after lists it")
    func justFinished() async throws {
        let (session, _) = try sessionWithRow()
        session.start(on: session.current.id)
        let finishing = try #require(session.loggedWorkout)
        session.finish()
        #expect(session.justFinished == finishing.id)
        // No wait for the write first: Log reads as the drawer closes over it, or at once with
        // VoiceOver or the app leaving the foreground.
        await session.refreshLog()
        #expect(session.log?.loggedWorkouts.map(\.id) == [finishing.id])
        session.takeJustFinished()
        #expect(session.justFinished == nil, "taken, it comes in once only")
    }

    /// Workouts tapped in a drawer swiped open during the finish's "++", before its way to Log.
    @Test("Workouts shown before Log takes the workout just finished leaves none for Log")
    func workoutsDropsJustFinished() throws {
        let (session, _) = try sessionWithRow()
        session.start(on: session.current.id)
        session.finish()
        #expect(session.justFinished != nil)
        session.showWorkouts()
        #expect(session.justFinished == nil, "a later Log would leave it out, then bring it in")
    }

    @Test("Discard names no workout for Log, and Log gains none")
    func discardNamesNone() async throws {
        let (session, _) = try sessionWithRow()
        session.start(on: session.current.id)
        session.discard()
        #expect(session.justFinished == nil)
        await session.refreshLog()
        #expect(session.log?.loggedWorkouts.isEmpty == true)
        #expect(session.screen == .workout, "the app stays on the workout")
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

    @Test("A row the open workout no longer has opens no sheet, as when tapped as it leaves")
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

    @Test("A wait outlived by a pop off the Workouts screen sets nothing")
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

    @Test("A workout opened from the list is pushed on it")
    func openFromList() async {
        let session = await pushedSession()
        #expect(session.screen == .pushedWorkout)
        #expect(session.current == saved)
        #expect(session.showing == .workout)
    }

    @Test("The open workout opened from the list is pushed on it as it is")
    func openOpenFromList() async {
        let session = session()
        session.showWorkouts()
        await session.open(session.current.id, weightUnit: .pounds)
        #expect(session.screen == .pushedWorkout)
        #expect(session.current.name == "Upper")
    }

    @Test("The list's + pushes a new workout on it, showing as the workout")
    func newFromList() async {
        let session = session()
        session.showWorkouts()
        await session.startNew()
        #expect(session.screen == .pushedWorkout)
        #expect(session.current.isEmpty)
        #expect(session.showing == .workout)
    }

    @Test("Back from a pushed workout shows the list again")
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

    @Test("Start on a pushed workout shows it in progress at the root, as it is now")
    func startPushed() async throws {
        let session = await pushedSession()
        let edited = try addingExercise(to: saved, in: session)
        session.start(on: session.current.id)
        #expect(session.screen == .workout)
        #expect(session.opened == edited)
        #expect(session.loggedWorkout?.workoutID == saved.id)
    }

    @Test("Start at the root keeps the screen the workout opened with")
    func startAtRoot() throws {
        let workout = Workout(name: "Upper")
        let session = session(workout)
        _ = try addingExercise(to: workout, in: session)
        session.start(on: session.current.id)
        #expect(session.screen == .workout)
        #expect(session.opened == workout)
    }
}
