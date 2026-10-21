import Foundation
import Testing
@testable import WorkoutStore

@Suite("Workout")
struct WorkoutTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1000)

    private func at(_ seconds: Double) -> Date {
        start.addingTimeInterval(seconds)
    }

    private let workout: Workout

    init() {
        workout = Workout(routineID: UUID(), routineName: "Upper", startedAt: start)
    }

    @Test("Running, the time is the time since Start, never below zero")
    func running() {
        #expect(workout.elapsed(at: at(0)) == .zero)
        #expect(workout.elapsed(at: at(252)) == .seconds(252))
        #expect(workout.elapsed(at: at(-30)) == .zero)
        #expect(workout.isInProgress)
        #expect(!workout.isPaused)
    }

    @Test("Fractions of a second round down")
    func roundsDown() {
        #expect(workout.elapsed(at: at(59.9)) == .seconds(59))
    }

    @Test("Paused, the time holds; resumed, it carries on from there")
    func pauseAndResume() {
        let paused = workout.pausing(at: at(60))
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
        let twice = workout
            .pausing(at: at(10)).resuming(at: at(20))
            .pausing(at: at(30)).resuming(at: at(45))
        #expect(twice.pausedSeconds == 25)
        #expect(twice.elapsed(at: at(100)) == .seconds(75))
        #expect(twice.pausing(at: at(100)).elapsed(at: at(900)) == .seconds(75))
    }

    @Test("Pausing a paused workout and resuming a running one change nothing")
    func noOps() {
        let paused = workout.pausing(at: at(10))
        #expect(paused.pausing(at: at(20)) == paused)
        #expect(workout.resuming(at: at(20)) == workout)
    }

    @Test("Finished, running or paused, the time is fixed whatever the clock")
    func finishing() {
        let finished = workout.finishing(at: at(300))
        #expect(!finished.isInProgress)
        #expect(finished.elapsed(at: at(9000)) == .seconds(300))
        let pausedThenFinished = workout.pausing(at: at(100)).finishing(at: at(300))
        #expect(pausedThenFinished.pausedSeconds == 200)
        #expect(pausedThenFinished.pausedAt == nil)
        #expect(!pausedThenFinished.isPaused)
        #expect(pausedThenFinished.elapsed(at: at(9000)) == .seconds(100))
        #expect(finished.finishing(at: at(400)) == finished)
        #expect(finished.pausing(at: at(400)) == finished)
    }

    @Test("The clock starts later by the time paused")
    func clockStart() {
        #expect(workout.pausing(at: at(10)).resuming(at: at(25)).clockStart == at(15))
    }
}

@Suite("Workout text")
struct WorkoutTextTests {
    private let locale = Locale(identifier: "en_US")

    @Test(
        "The time reads in minutes and seconds under an hour, with hours from one",
        arguments: [
            (0, "00:00"), (59, "00:59"), (60, "01:00"), (3599, "59:59"),
            (3600, "1:00:00"), (3852, "1:04:12"), (36000, "10:00:00"),
        ],
    )
    func elapsedText(seconds: Int, text: String) {
        #expect(Workout.elapsedText(.seconds(seconds), locale: locale) == text)
    }

    @Test(
        "The time reads in words to VoiceOver",
        arguments: [
            (252, "4 minutes, 12 seconds"), (3852, "1 hour, 4 minutes, 12 seconds"),
            (0, "0 seconds"),
        ],
    )
    func spokenElapsed(seconds: Int, text: String) {
        #expect(Workout.spokenElapsed(.seconds(seconds), locale: locale) == text)
    }
}
