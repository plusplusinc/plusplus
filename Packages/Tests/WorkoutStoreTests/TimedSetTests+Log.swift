import Foundation
import Testing
@testable import WorkoutStore

/// What a timed set stores when the workout is finished over it, and the time of day a log
/// stores: a count's end when it ran out unseen, the tap's moment otherwise.
extension TimedSetTests {
    @Test("Finish mid-count logs the time done and +15 s taps, as Log early then does")
    func finishedMidCount() throws {
        let begun = try Self.started(Self.workout())
        // Counting from 10, +15 s at 12: 18 s done at 28.
        let live = LiveWorkout(
            workout: begun.workout,
            loggedWorkout: begun.extendingCount(by: 15, at: Self.at(12)),
        )
        let finished = live.finishing(at: Self.at(28))
        #expect(finished.sets.count == 1)
        let set = try #require(finished.sets.first)
        #expect(set.target == .time(seconds: 18))
        #expect(finished.count == nil)
        #expect(finished.endedAt == Self.at(28))
        let early = try #require(Self.logged(live, at: 28).loggedWorkout.sets.first)
        #expect(early.target == set.target)
        #expect(early.timeAdded == set.timeAdded)
        #expect(early.loggedAt == set.loggedAt)
        #expect(early.clockWhenLogged == set.clockWhenLogged)
    }

    @Test("Finish while paused mid-count logs the set where the pause stopped it")
    func finishedPausedMidCount() throws {
        let live = try Self.started(Self.workout())
        // Counting from 10, paused at 22 with 12 s done; finished ten minutes on.
        let paused = LiveWorkout(
            workout: live.workout,
            loggedWorkout: live.loggedWorkout.pausing(at: Self.at(22)),
        )
        let set = try #require(paused.finishing(at: Self.at(622)).sets.first)
        #expect(set.target == .time(seconds: 12))
        #expect(set.loggedAt == Self.at(22))
        #expect(set.clockWhenLogged == 22)
    }

    @Test("Finish during Starts in logs nothing for the set")
    func finishedInStartsIn() throws {
        let finished = try Self.started(Self.workout()).finishing(at: Self.at(5))
        #expect(finished.sets.isEmpty)
        #expect(finished.count == nil)
        #expect(finished.endedAt == Self.at(5))
    }

    @Test("Finish after a count ran out unlogged logs it at full time, at its end's time of day")
    func finishedAfterRunOut() throws {
        let finished = try Self.started(Self.workout()).finishing(at: Self.at(58))
        let set = try #require(finished.sets.first)
        #expect(set.target == .time(seconds: 30))
        #expect(set.loggedAt == Self.at(40))
    }

    @Test("A count logged after it ran out stores the time of day it ended, not the log's")
    func runOutTimeOfDay() throws {
        let begun = try Self.started(Self.workout())
        // Paused from 2 to 12 during Starts in: the count runs on the clock from 10 to 40, 20 to
        // 50 by the time of day.
        let paused = begun.loggedWorkout.pausing(at: Self.at(2)).resuming(at: Self.at(12))
        let live = LiveWorkout(workout: begun.workout, loggedWorkout: paused)
        // The phone woke 18 s after the end.
        let set = try #require(Self.logged(live, at: 68).loggedWorkout.sets.first)
        #expect(set.loggedAt == Self.at(50))
        #expect(set.clockWhenLogged == 40, "The rest after it starts where the count ended")
        #expect(set.target == .time(seconds: 30))
    }

    @Test("A set logged by a tap stores the moment of the tap: Log early, and reps")
    func tapTimeOfDay() throws {
        let live = try Self.started(Self.workout())
        #expect(try Self.logged(live, at: 28).loggedWorkout.sets.first?.loggedAt == Self.at(28))
        let workout = try Workout(exercises: [WorkoutExercise.builtIn("Push-up") { $0.sets = 1 }])
        let reps = try Self.logged(Self.started(workout), at: 5)
        #expect(reps.loggedWorkout.sets.first?.loggedAt == Self.at(5))
    }
}
