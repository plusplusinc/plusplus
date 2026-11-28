import Foundation
import Testing
@testable import WorkoutStore

@Suite("Workout session")
struct WorkoutSessionTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1000)

    private func at(_ seconds: Double) -> Date {
        start.addingTimeInterval(seconds)
    }

    private let workoutSession: WorkoutSession

    init() {
        workoutSession = WorkoutSession(workoutID: UUID(), workoutName: "Upper", startedAt: start)
    }

    @Test("Running, the time is the time since Start, never below zero")
    func running() {
        #expect(workoutSession.elapsed(at: at(0)) == .zero)
        #expect(workoutSession.elapsed(at: at(252)) == .seconds(252))
        #expect(workoutSession.elapsed(at: at(-30)) == .zero)
        #expect(workoutSession.isInProgress)
        #expect(!workoutSession.isPaused)
    }

    @Test("Fractions of a second round down")
    func roundsDown() {
        #expect(workoutSession.elapsed(at: at(59.9)) == .seconds(59))
    }

    @Test("Paused, the time holds; resumed, it carries on from there")
    func pauseAndResume() {
        let paused = workoutSession.pausing(at: at(60))
        #expect(paused.isPaused)
        #expect(paused.elapsed(at: at(60)) == .seconds(60))
        #expect(paused.elapsed(at: at(500)) == .seconds(60))
        let resumed = paused.resuming(at: at(100))
        #expect(!resumed.isPaused)
        #expect(resumed.pausedSeconds == 40)
        #expect(resumed.elapsed(at: at(110)) == .seconds(70))
    }

    @Test("Two pauses add up")
    func twoPauses() {
        let twice = workoutSession
            .pausing(at: at(10)).resuming(at: at(20))
            .pausing(at: at(30)).resuming(at: at(45))
        #expect(twice.pausedSeconds == 25)
        #expect(twice.elapsed(at: at(100)) == .seconds(75))
        #expect(twice.pausing(at: at(100)).elapsed(at: at(900)) == .seconds(75))
    }

    @Test("Each resume keeps its pause's times, and a finish while paused keeps the last")
    func pausesKept() {
        let twice = workoutSession
            .pausing(at: at(10)).resuming(at: at(20))
            .pausing(at: at(30)).resuming(at: at(45))
        #expect(twice.pauses == [
            DateInterval(start: at(10), end: at(20)),
            DateInterval(start: at(30), end: at(45)),
        ])
        let finished = twice.pausing(at: at(60)).finishing(at: at(100))
        #expect(finished.pauses.last == DateInterval(start: at(60), end: at(100)))
        #expect(finished.pauses.reduce(0) { $0 + $1.duration } == finished.pausedSeconds)
        // A resume read off a clock set back keeps a pause of no length, not one reversed.
        let setBack = workoutSession.pausing(at: at(50)).resuming(at: at(40))
        #expect(setBack.pauses == [DateInterval(start: at(50), duration: 0)])
    }

    /// Started at 0 with its time due at 10, as through the first set's "Start in".
    private var startingIn: WorkoutSession {
        var early = workoutSession
        early.startedAt = at(10)
        return early
    }

    @Test("A pause before the time starts moves the start on, the clock unchanged, no pause kept")
    func pauseBeforeStart() throws {
        let paused = startingIn.pausing(at: at(2))
        let resumed = paused.resuming(at: at(5))
        #expect(resumed.startedAt == at(13))
        #expect(resumed.pauses.isEmpty)
        #expect(resumed.pausedSeconds == 0)
        #expect(resumed.clock(at: at(5)) == paused.clock(at: at(5)))
        #expect(resumed.clock(at: at(9)) == startingIn.clock(at: at(6)))
        // "Start in" runs out and a set is logged as usual: Health gets the start, no pause.
        let row = try WorkoutExercise.builtIn("Push-up")
        let finished = resumed
            .logging(PlannedSet(row: row.id, round: 1), of: row, at: at(20))
            .finishing(at: at(30))
        let health = try HealthWorkout(finished, in: .builtIn)
        #expect(health.start == at(13))
        #expect(health.pauses.isEmpty)
    }

    @Test("A set logged ahead of the clock starts the time at the log, after a pause too")
    func startingClockAfterPause() throws {
        let row = try WorkoutExercise.builtIn("Push-up")
        let paused = startingIn.pausing(at: at(2)).resuming(at: at(5))
        let logged = paused.logging(PlannedSet(row: row.id, round: 1), of: row, at: at(8))
        #expect(logged.startedAt == at(8))
        #expect(logged.pauses.isEmpty)
        #expect(logged.clock(at: at(8)) == 0)
    }

    @Test("Pausing a paused workout and resuming a running one change nothing")
    func noOps() {
        let paused = workoutSession.pausing(at: at(10))
        #expect(paused.pausing(at: at(20)) == paused)
        #expect(workoutSession.resuming(at: at(20)) == workoutSession)
    }

    @Test("Finished, running or paused, the time is fixed whatever the clock")
    func finishing() {
        let finished = workoutSession.finishing(at: at(300))
        #expect(!finished.isInProgress)
        #expect(finished.elapsed(at: at(9000)) == .seconds(300))
        let pausedThenFinished = workoutSession.pausing(at: at(100)).finishing(at: at(300))
        #expect(pausedThenFinished.pausedSeconds == 200)
        #expect(pausedThenFinished.pausedAt == nil)
        #expect(!pausedThenFinished.isPaused)
        #expect(pausedThenFinished.elapsed(at: at(9000)) == .seconds(100))
        #expect(finished.finishing(at: at(400)) == finished)
        #expect(finished.pausing(at: at(400)) == finished)
    }

    @Test("The clock starts later by the time paused")
    func clockStart() {
        #expect(workoutSession.pausing(at: at(10)).resuming(at: at(25)).clockStart == at(15))
    }

    @Test("The time next turns over on the clock's whole seconds, from the start or past a pause")
    func nextSecond() {
        #expect(workoutSession.nextSecond(after: at(0)) == at(1))
        #expect(workoutSession.nextSecond(after: at(4.3)) == at(5))
        #expect(workoutSession.nextSecond(after: at(5)) == at(6))
        let resumed = workoutSession.pausing(at: at(10)).resuming(at: at(25.4))
        #expect(resumed.nextSecond(after: at(30)) == at(30.4))
        #expect(resumed.nextSecond(after: at(30.4)) == at(31.4))
    }

    @Test("Ending offers Finish only once a set is logged, and only while in progress")
    func offersFinish() throws {
        #expect(!workoutSession.offersFinish)
        let row = try WorkoutExercise.builtIn("Push-up")
        let done = workoutSession.logging(PlannedSet(row: row.id, round: 1), of: row, at: at(30))
        #expect(done.offersFinish)
        #expect(!done.finishing(at: at(300)).offersFinish)
    }
}

@Suite("Workout session text")
struct WorkoutSessionTextTests {
    private let locale = Locale(identifier: "en_US")

    @Test(
        "The time reads in minutes and seconds under an hour, with hours from one",
        arguments: [
            (0, "00:00"), (59, "00:59"), (60, "01:00"), (3599, "59:59"),
            (3600, "1:00:00"), (3852, "1:04:12"), (36000, "10:00:00"),
        ],
    )
    func elapsedText(seconds: Int, text: String) {
        #expect(WorkoutSession.elapsedText(.seconds(seconds), locale: locale) == text)
    }

    @Test(
        "The time reads in words to VoiceOver",
        arguments: [
            (252, "4 minutes, 12 seconds"), (3852, "1 hour, 4 minutes, 12 seconds"),
            (0, "0 seconds"),
        ],
    )
    func spokenElapsed(seconds: Int, text: String) {
        #expect(WorkoutSession.spokenElapsed(.seconds(seconds), locale: locale) == text)
    }
}
