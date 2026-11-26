import Foundation
import Testing
@testable import WorkoutStore

extension TimedSetTests {
    @Test(
        "A skipped rest holds its time a moment: the timed set next, begun at the tap, then counts",
    )
    func restSkipped() throws {
        let live = try Self.started(Self.workout(rest: 30))
        let after = try Self.logged(live, at: 45)
        // The rest runs from 40 to 70; skipped at 63.5, between two sets of one exercise.
        let tap = 63.5
        let cut = LiveWorkout(
            workout: after.workout,
            loggedWorkout: after.skippingRest(at: Self.at(tap)),
        )
        let timed = try #require(cut.timedSet, "Begun at the tap, not at the rest's end")
        let held = tap + LiveWorkout.skipHold
        #expect(timed.startClock == held, "To the fraction of a second")
        #expect(cut.countStage(at: Self.at(tap)) == .startIn, "Waiting, the rest's time held")
        #expect(cut.countStage(at: Self.at(held)) == .counting)
        // The rest moves on as the count begins, and no sooner, its stored length kept.
        let rest = try #require(cut.rest())
        #expect(rest.leaveClock == held)
        #expect(!rest.isOver(atClock: tap))
        #expect(rest.endClock == 70)
        #expect(rest.shownLeft(atClock: held) == 70 - tap)
        // The screen's own begin, as the rest moves on, changes nothing.
        #expect(cut.beginningCount(at: Self.at(held + 0.1)) == cut.loggedWorkout)
        // Nor does a second Skip rest or +15 s, in the hold or after it.
        for second in [tap + 0.1, held + 0.1] {
            #expect(cut.skippingRest(at: Self.at(second)) == cut.loggedWorkout)
            #expect(cut.extendingRest(by: 15, at: Self.at(second)) == cut.loggedWorkout)
        }
    }

    @Test("Skipped before another exercise, the next set gets its full Start in after the hold")
    func restSkippedOntoExercise() throws {
        var plank = try WorkoutExercise.builtIn("Plank") { $0.sets = 1 }
        plank.plan.target = .time(seconds: 30)
        plank.setRest(30)
        let push = try WorkoutExercise.builtIn("Push-up") { $0.sets = 1 }
        let live = Self.started(Workout(exercises: [plank, push]))
        let after = try Self.logged(live, at: 40)
        // The rest runs from 40 to 70; skipped at 52.5.
        let tap = 52.5
        let cut = LiveWorkout(
            workout: after.workout,
            loggedWorkout: after.skippingRest(at: Self.at(tap)),
        )
        let leave = tap + LiveWorkout.skipHold
        #expect(cut.rest()?.leaveClock == leave)
        // All of "Start in" and its hold come after the move.
        #expect(cut.loggedWorkout.count?.startClock == leave + Self.lead)
        #expect(cut.countStage(at: Self.at(leave + 0.1)) == .startIn)
        // Reopened in the hold, the screen opens in the rest; after it, on "Start in".
        let inHold = WorkoutPhase(resuming: cut, at: Self.at(tap + 0.1))
        #expect(inHold.resting != nil)
        #expect(WorkoutPhase(resuming: cut, at: Self.at(leave)) == .timing(.startIn))
    }

    @Test("A skip's count begins where its rest moves on, at any tap, its last second included")
    func skipCountFollowsLeave() throws {
        var plank = try WorkoutExercise.builtIn("Plank") { $0.sets = 1 }
        plank.plan.target = .time(seconds: 30)
        plank.setRest(30)
        let push = try WorkoutExercise.builtIn("Push-up") { $0.sets = 1 }
        let after = try Self.logged(Self.started(Workout(exercises: [plank, push])), at: 40)
        // The rest runs from 40 to 70: early, midway, and with under `skipHold` left.
        for tap in [40.1, 55.0, 69.9] {
            let cut = LiveWorkout(
                workout: after.workout,
                loggedWorkout: after.skippingRest(at: Self.at(tap)),
            )
            let rest = try #require(cut.rest())
            let count = try #require(cut.loggedWorkout.count)
            #expect(count.startClock == rest.leaveClock + Self.lead, "Tapped at \(tap)")
            // Its count keeps the time it had through the hold, though 0:00 comes in it.
            #expect(rest.shownLeft(atClock: rest.leaveClock - 0.01) > 0, "Tapped at \(tap)")
        }
    }

    @Test("A rest an edit lengthens once its set's count began takes no Skip rest or +15 s")
    func countBegunTakesNoRestTaps() throws {
        let after = try Self.logged(Self.started(Self.workout(rest: 30)), at: 45)
        // The rest runs from 40 to 70; the next plank counts from its move on, at 71.
        let begun = LiveWorkout(
            workout: after.workout,
            loggedWorkout: after.beginningCount(at: Self.at(71.2)),
        )
        let count = try #require(begun.setCount)
        var workout = begun.workout
        workout.exercises[0].setRest(90)
        let edited = LiveWorkout(workout: workout, loggedWorkout: begun.loggedWorkout)
        // The rest runs to 130 now, while the plank counts: a tap would begin the set over.
        #expect(try #require(edited.rest()).takesTaps(atClock: 75))
        #expect(edited.skippingRest(at: Self.at(75)) == edited.loggedWorkout)
        #expect(edited.extendingRest(by: 15, at: Self.at(75)) == edited.loggedWorkout)
        #expect(edited.setCount == count)
    }
}
