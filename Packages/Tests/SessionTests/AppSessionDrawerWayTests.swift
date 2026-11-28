import Foundation
import Testing
@testable import Session
@testable import WorkoutStore

/// Going to a place by way of the drawer (`show(_:after:throughDrawer:markWait:)`): its beats in
/// order
/// on a stepped clock, and what ends it early. The durations are this test's own, not the app's.
@Suite("Workout session: a place by way of the drawer")
struct AppSessionDrawerWayTests {
    private let clock = StepClock()
    private let opening = AppSession.DrawerOpening(
        arrival: .seconds(1),
        holdBefore: .seconds(2),
        holdAfter: .seconds(3),
    )
    private let markWait = Duration.seconds(4)

    /// A session showing Log, its beats on the stepped clock.
    private func session() -> AppSession {
        let session = AppSession(
            workout: Workout(name: "Upper"),
            store: nil,
            namer: .muscleGroupsOnly,
        )
        session.beatClock = clock
        session.showLog()
        return session
    }

    @Test("From a closed drawer: it opens, holds, the mark moves, it holds, then lands closed")
    func fromClosedDrawer() async throws {
        let session = session()
        session.show(.workouts, throughDrawer: opening, markWait: markWait)
        let way = try #require(session.throughDrawer)
        #expect(session.isDrawerOpen)
        #expect(session.drawerMark == nil)
        #expect(session.showing == .log)

        await clock.sleeper()
        clock.advance(by: .milliseconds(2999))
        #expect(clock.hasSleeper, "the mark waits for the opening and its hold")

        clock.advance(by: .milliseconds(1))
        await clock.sleeper()
        #expect(session.drawerMark == .workouts)
        #expect(session.isDrawerOpen)
        #expect(session.screen == .log, "the place swaps only as the drawer closes")

        clock.advance(by: .milliseconds(6999))
        #expect(clock.hasSleeper, "the drawer waits for the mark and the hold after it")
        clock.advance(by: .milliseconds(1))
        await way.value
        #expect(session.screen == .workouts)
        #expect(!session.isDrawerOpen)
        #expect(session.drawerMark == .workouts, "the closing drawer keeps its mark")

        session.openDrawer()
        #expect(session.drawerMark == nil, "a drawer opened again marks what shows")
    }

    @Test("From an open drawer, as a row is tapped: the mark moves at once, the close follows it")
    func fromOpenDrawer() async throws {
        let session = session()
        session.openDrawer()
        session.show(.workouts, throughDrawer: opening, markWait: markWait)
        let way = try #require(session.throughDrawer)

        await clock.sleeper()
        #expect(session.drawerMark == .workouts)
        #expect(session.isDrawerOpen)

        clock.advance(by: markWait)
        await way.value
        #expect(session.screen == .workouts)
        #expect(!session.isDrawerOpen)
    }

    @Test("A second way asked for while one plays is ignored")
    func secondAskIgnored() async throws {
        let session = session()
        session.openDrawer()
        session.show(.workouts, throughDrawer: opening, markWait: markWait)
        let way = try #require(session.throughDrawer)
        session.show(.log, throughDrawer: opening, markWait: markWait)
        #expect(session.throughDrawer == way)

        await clock.sleeper()
        clock.advance(by: markWait)
        await way.value
        #expect(session.screen == .workouts)
    }

    @Test("A close mid-way, a tap beside the drawer or a swipe, lands on the place at once")
    func closeMidWay() async throws {
        let session = session()
        session.show(.workouts, throughDrawer: opening, markWait: markWait)
        let way = try #require(session.throughDrawer)
        await clock.sleeper()

        session.closeDrawer()
        await way.value
        #expect(session.screen == .workouts)
        #expect(!session.isDrawerOpen)
        #expect(session.drawerMark == nil)
        #expect(!clock.hasSleeper, "no beat is left to run")

        // The way is over, so a new one plays.
        session.show(.log, throughDrawer: opening, markWait: markWait)
        #expect(session.throughDrawer != nil)
    }

    @Test("Leaving the app mid-way lands on the place, closed; with no way under way, nothing")
    func finishThroughDrawer() async throws {
        let session = session()
        session.openDrawer()
        session.finishThroughDrawer()
        #expect(session.isDrawerOpen, "a drawer the person opened stays open")
        session.closeDrawer()

        session.show(.workouts, throughDrawer: opening, markWait: markWait)
        let way = try #require(session.throughDrawer)
        await clock.sleeper()
        clock.advance(by: .seconds(3))
        await clock.sleeper()
        session.finishThroughDrawer()
        await way.value
        #expect(session.screen == .workouts)
        #expect(!session.isDrawerOpen)
    }

    @Test("A workout pushed mid-way ends the way, so no late close pops it")
    func workoutPushedMidWay() async throws {
        let session = session()
        session.show(.workouts, throughDrawer: opening, markWait: markWait)
        let way = try #require(session.throughDrawer)
        await clock.sleeper()

        await session.startNew()
        let lingering = clock.hasSleeper
        #expect(!lingering, "no beat is left to land on Workouts")
        if lingering {
            way.cancel()
        }
        await way.value
        #expect(session.screen == .pushedWorkout)
        #expect(session.throughDrawer == nil)
    }

    private let lead = Duration.seconds(5)

    /// A session that has just finished a workout pushed from the Workouts list, its beats on
    /// the stepped clock.
    private func finishedSession() async throws -> AppSession {
        let exercise = try #require(Exercise.builtIn(id: "barbell-bench-press"))
        let session = AppSession(workout: Workout(), store: nil, namer: .muscleGroupsOnly)
        session.beatClock = clock
        session.showWorkouts()
        await session.startNew()
        var workout = session.current
        workout.exercises = [WorkoutExercise(exercise: exercise, weightUnit: .pounds)]
        session.save(workout)
        session.start(on: workout.id)
        session.finish()
        return session
    }

    @Test(
        "With a lead, as after a finish, the drawer stays shut until it passes, then plays to Log",
    )
    func lead() async throws {
        let session = try await finishedSession()
        let finished = try #require(session.justFinished)
        session.show(.log, after: lead, throughDrawer: opening, markWait: markWait)
        #expect(!session.isDrawerOpen, "the drawer waits out the lead")
        await clock.sleeper()
        clock.advance(by: lead - .milliseconds(1))
        #expect(!session.isDrawerOpen)
        #expect(session.screen == .pushedWorkout)

        clock.advance(by: .milliseconds(1))
        await clock.sleeper()
        #expect(session.isDrawerOpen)
        #expect(session.drawerMark == nil, "the drawer marks the workout showing, on Workouts")
        let way = try #require(session.throughDrawer)
        clock.advance(by: .seconds(3))
        await clock.sleeper()
        #expect(session.drawerMark == .log)
        clock.advance(by: .seconds(7))
        await way.value
        #expect(session.screen == .log)
        #expect(!session.screen.isPushed, "Log shows no back button")
        #expect(!session.isDrawerOpen)
        #expect(session.justFinished == finished, "Log has yet to bring the workout in")
    }

    @Test("A close or the app leaving during the lead lands on Log at once, closed")
    func endedDuringLead() async throws {
        for end in [AppSession.closeDrawer, AppSession.finishThroughDrawer] {
            let session = try await finishedSession()
            session.show(.log, after: lead, throughDrawer: opening, markWait: markWait)
            let wait = try #require(session.throughDrawer)
            await clock.sleeper()
            end(session)()
            await wait.value
            #expect(session.screen == .log)
            #expect(!session.isDrawerOpen)
            #expect(session.throughDrawer == nil)
            #expect(!clock.hasSleeper, "no beat is left to open the drawer")
            #expect(session.justFinished != nil, "Log still brings the workout in")
        }
    }

    @Test("Through a finish's lead the drawer is locked: only the way opens it")
    func lockedDuringLead() async throws {
        let session = try await finishedSession()
        #expect(!session.isDrawerLocked, "a finished workout leaves the drawer unlocked")
        session.show(.log, after: lead, throughDrawer: opening, markWait: markWait)
        #expect(session.isDrawerLocked)
        session.openDrawer()
        #expect(!session.isDrawerOpen, "++ and a swipe open nothing during the lead")

        await clock.sleeper()
        clock.advance(by: lead)
        await clock.sleeper()
        #expect(session.isDrawerOpen, "the way opens it")
        #expect(!session.isDrawerLocked)
    }

    @Test("Whatever ends a finish's lead leaves the drawer unlocked")
    func leadEndersUnlock() async throws {
        let enders: [(AppSession) -> Void] = [
            { $0.closeDrawer() },
            { $0.finishThroughDrawer() },
            { $0.showWorkouts() },
            { $0.showLog() },
        ]
        for end in enders {
            let session = try await finishedSession()
            session.show(.log, after: lead, throughDrawer: opening, markWait: markWait)
            let wait = try #require(session.throughDrawer)
            await clock.sleeper()
            end(session)
            await wait.value
            #expect(!session.isDrawerLocked)
            session.openDrawer()
            #expect(session.isDrawerOpen)
        }
    }

    @Test("Where the drawer is kept shut, as under a row's sheet, it goes straight there")
    func drawerKeptShut() throws {
        let exercise = try #require(Exercise.builtIn(id: "barbell-bench-press"))
        let row = WorkoutExercise(exercise: exercise, weightUnit: .pounds)
        let session = AppSession(
            workout: Workout(name: "Upper", exercises: [row]),
            store: nil,
            namer: .muscleGroupsOnly,
        )
        session.beatClock = clock
        session.openRowSheet(RowSheet(id: row.id, opensCustomizing: false))
        session.show(.log, throughDrawer: opening, markWait: markWait)
        #expect(session.screen == .log)
        #expect(!session.isDrawerOpen)
        #expect(session.throughDrawer == nil)
        #expect(!clock.hasSleeper)
    }
}
