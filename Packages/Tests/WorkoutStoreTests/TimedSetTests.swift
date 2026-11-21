import Foundation
import Testing
@testable import WorkoutStore

/// A timed set's count on the workout's clock: when it begins, "Starts in", the time done at a
/// log, +15 s, the rest after it, and a count that ran out while the app was away.
@Suite("Timed set")
struct TimedSetTests {
    static let start = Date(timeIntervalSinceReferenceDate: 1000)

    /// `start` plus `seconds`.
    static func at(_ seconds: Double) -> Date {
        start.addingTimeInterval(seconds)
    }

    /// A plank, 3 × 30 s resting `rest` s between sets, then a side plank, 1 × 20 s per side,
    /// then push-ups.
    static func workout(rest: Int = 0) throws -> Workout {
        var plank = try WorkoutExercise.builtIn("Plank") { $0.sets = 3 }
        plank.plan.target = .time(seconds: 30)
        plank.setRest(rest)
        var side = try WorkoutExercise.builtIn("Side plank") { $0.sets = 1 }
        side.plan.target = .time(seconds: 20)
        side.setRest(0)
        let push = try WorkoutExercise.builtIn("Push-up") { $0.sets = 1 }
        return Workout(exercises: [plank, side, push])
    }

    /// `workout` as Start begins it, at `start`.
    static func started(_ workout: Workout) -> LiveWorkout {
        let loggedWorkout = LoggedWorkout(
            workoutID: workout.id,
            workoutName: "Test",
            startedAt: start,
        )
        let begun = LiveWorkout(workout: workout, loggedWorkout: loggedWorkout)
            .beginningCount(at: start)
        return LiveWorkout(workout: workout, loggedWorkout: begun)
    }

    /// `live` with its current set logged at `seconds`.
    static func logged(_ live: LiveWorkout, at seconds: Double) throws -> LiveWorkout {
        let set = try #require(live.currentSet)
        let row = try #require(live.currentExercise)
        return LiveWorkout(
            workout: live.workout,
            loggedWorkout: live.logging(set, of: row, at: at(seconds)),
        )
    }

    @Test("Start on a plank begins a count 10 s ahead; at 10 s it counts, 30 s left")
    func startsIn() throws {
        let live = try Self.started(Self.workout())
        let timed = try #require(live.timedSet)
        #expect(timed.startClock == 10)
        #expect(live.countStage(at: Self.at(3)) == .startsIn)
        #expect(timed.startsIn(atClock: 3) == 7)
        #expect(live.countStage(at: Self.at(10)) == .counting)
        #expect(timed.remaining(atClock: 10) == 30)
    }

    @Test("Start now moves the count's start to now; once the set counts it changes nothing")
    func startNow() throws {
        let live = try Self.started(Self.workout())
        let now = LiveWorkout(
            workout: live.workout,
            loggedWorkout: live.startingCountNow(at: Self.at(4)),
        )
        #expect(now.timedSet?.startClock == 4)
        let counting = now.startingCountNow(at: Self.at(6))
        #expect(counting == now.loggedWorkout)
    }

    @Test("At zero the set logs its full time, its clock the count's end, however late")
    func runOut() throws {
        let live = try Self.started(Self.workout(rest: 60))
        let after = try Self.logged(live, at: 45)
        let set = try #require(after.loggedWorkout.sets.first)
        #expect(set.target == .time(seconds: 30))
        #expect(set.plannedTarget == .time(seconds: 30))
        #expect(set.clockWhenLogged == 40)
        #expect(after.rest()?.startClock == 40)
        // The rest still runs: no count begins.
        #expect(after.loggedWorkout.count == nil)
    }

    @Test("A log with 17 to 18 s left stores 12 done of 30")
    func earlyLog() throws {
        let live = try Self.started(Self.workout())
        let after = try Self.logged(live, at: 10 + 12.5)
        #expect(after.loggedWorkout.sets.first?.target == .time(seconds: 12))
        #expect(after.loggedWorkout.sets.first?.clockWhenLogged == 22.5)
    }

    @Test("+15 s adds to this set only, never during Starts in or once over")
    func extend() throws {
        let live = try Self.started(Self.workout())
        #expect(live.extendingCount(by: 15, at: Self.at(5)) == live.loggedWorkout)
        let extended = LiveWorkout(
            workout: live.workout,
            loggedWorkout: live.extendingCount(by: 15, at: Self.at(30)),
        )
        #expect(extended.timedSet?.length == 45)
        #expect(extended.timedSet?.remaining(atClock: 30) == 25)
        #expect(extended.extendingCount(by: 15, at: Self.at(55)) == extended.loggedWorkout)
        let after = try Self.logged(extended, at: 55)
        #expect(after.loggedWorkout.sets.first?.target == .time(seconds: 45))
        #expect(after.loggedWorkout.sets.first?.timeAdded == 15)
        #expect(Self.landed(after, at: 56).timedSet?.length == 30)
    }

    /// `live` as the screen lands on its current set at `seconds`, beginning its count.
    private static func landed(_ live: LiveWorkout, at seconds: Double) -> LiveWorkout {
        LiveWorkout(workout: live.workout, loggedWorkout: live.beginningCount(at: at(seconds)))
    }

    @Test("A log begins no count: with no rest before it, Starts in begins as the screen lands")
    func startsInAtLanding() throws {
        let live = try Self.started(Self.workout())
        let after = try Self.logged(live, at: 40)
        #expect(after.loggedWorkout.count == nil)
        // Landed 0.75 s after the log: its ten seconds are all from there.
        let landed = Self.landed(after, at: 40.75)
        #expect(landed.timedSet?.startClock == 50.75)
        #expect(landed.timedSet?.startsIn(atClock: 40.75) == 10)
    }

    @Test("A skipped rest ends now: the timed set next counts from the tap")
    func restSkipped() throws {
        let live = try Self.started(Self.workout(rest: 30))
        let after = try Self.logged(live, at: 45)
        // The rest runs from 40 to 70; skipped at 63.
        let cut = LiveWorkout(
            workout: after.workout,
            loggedWorkout: after.skippingRest(at: Self.at(63)),
        )
        let timed = try #require(cut.timedSet, "Begun at the tap, not at the rest's end")
        #expect(timed.startClock == 63)
        #expect(cut.countStage(at: Self.at(63)) == .counting)
        // The screen's own begin, as the rest ends, changes nothing.
        #expect(cut.beginningCount(at: Self.at(63.1)) == cut.loggedWorkout)
    }

    @Test("A rest that just ended starts the count at its end; while it runs, none begins")
    func fromRest() throws {
        let live = try Self.started(Self.workout(rest: 20))
        let after = try Self.logged(live, at: 40)
        #expect(after.beginningCount(at: Self.at(50)) == after.loggedWorkout)
        let begun = LiveWorkout(
            workout: after.workout,
            loggedWorkout: after.beginningCount(at: Self.at(60.5)),
        )
        #expect(begun.timedSet?.startClock == 60)
        #expect(begun.countStage(at: Self.at(60.5)) == .counting)
    }

    @Test("A rest that ended long ago opens on Starts in from now")
    func afterAway() throws {
        let live = try Self.started(Self.workout(rest: 20))
        let after = try Self.logged(live, at: 40)
        let begun = LiveWorkout(
            workout: after.workout,
            loggedWorkout: after.beginningCount(at: Self.at(100)),
        )
        #expect(begun.timedSet?.startClock == 110)
    }

    @Test("Between a set's sides, the right side gets Starts in as it shows")
    func sides() throws {
        var live = try Self.started(Self.workout())
        for second in [40.0, 80, 120] {
            live = try Self.landed(Self.logged(live, at: second), at: second)
        }
        #expect(live.currentSet?.side == .left)
        let left = try #require(live.timedSet)
        live = try Self.logged(live, at: left.endClock)
        #expect(live.currentSet?.side == .right)
        live = Self.landed(live, at: left.endClock + 0.5)
        #expect(live.timedSet?.startClock == left.endClock + 10.5)
    }

    @Test("A pause stops the count; resumed, it carries on")
    func pause() throws {
        let live = try Self.started(Self.workout())
        let paused = live.loggedWorkout.pausing(at: Self.at(20)).resuming(at: Self.at(80))
        let resumed = LiveWorkout(workout: live.workout, loggedWorkout: paused)
        #expect(resumed.timedSet?.remaining(atClock: paused.clock(at: Self.at(80))) == 20)
    }

    @Test("A count over at launch logs at full time, once; the next set's begins from now")
    func caughtUp() throws {
        let live = try Self.started(Self.workout())
        let caught = LiveWorkout(
            workout: live.workout,
            loggedWorkout: live.caughtUp(at: Self.at(300)),
        )
        #expect(caught.loggedWorkout.sets.count == 1)
        #expect(caught.loggedWorkout.sets.first?.clockWhenLogged == 40)
        #expect(caught.timedSet?.startClock == 310)
    }

    @Test("A count begun for another set is none: the row changed to reps")
    func otherSet() throws {
        var live = try Self.started(Self.workout())
        live.workout.exercises[0].plan.target = .reps(10)
        #expect(live.timedSet == nil)
        #expect(live.countStage(at: Self.at(20)) == nil)
    }

    @Test("A timed set an edit makes current mid-count opens on Starts in from the edit")
    func editMakesCurrent() throws {
        var live = try Self.started(Self.workout())
        // The plank counts from 10; at 20 a side plank is moved ahead of it.
        let side = live.workout.exercises.remove(at: 1)
        live.workout.exercises.insert(side, at: 0)
        #expect(live.timedSet == nil, "The plank's count stays with the plank")
        let begun = LiveWorkout(
            workout: live.workout,
            loggedWorkout: live.beginningCount(at: Self.at(20)),
        )
        #expect(begun.currentSet?.row == side.id)
        #expect(begun.timedSet?.startClock == 30)
        #expect(begun.countStage(at: Self.at(20)) == .startsIn)
    }

    @Test("A time changed mid-count keeps its start; cut below the time done, it logs that time")
    func timeChangedMidCount() throws {
        var live = try Self.started(Self.workout())
        // Counting from 10; at 15, 5 s done, 25 left.
        live.workout.exercises[0].plan.target = .time(seconds: 20)
        let longer = try #require(live.timedSet)
        #expect(longer.startClock == 10)
        #expect(longer.remaining(atClock: 15) == 15)
        #expect(
            live.beginningCount(at: Self.at(15)) == live.loggedWorkout,
            "No second count begins",
        )
        live.workout.exercises[0].plan.target = .time(seconds: 3)
        let shorter = try #require(live.timedSet)
        #expect(shorter.isOver(atClock: 15))
        let after = try Self.logged(live, at: 15)
        let set = try #require(after.loggedWorkout.sets.first)
        #expect(set.target == .time(seconds: 3))
        #expect(set.clockWhenLogged == 13)
    }

    @Test("An edit settles the phase only at rest: onto a count, off one, never mid-sequence")
    func settleCount() throws {
        var running = WorkoutPhase.running
        let ontoCount = running.settleCount(on: .startsIn)
        #expect(ontoCount)
        #expect(running == .timing(.startsIn))
        var timing = WorkoutPhase.timing(.counting)
        let offCount = timing.settleCount(on: nil)
        #expect(offCount, "The row changed to reps")
        #expect(timing == .running)
        var same = WorkoutPhase.timing(.startsIn)
        let unchanged = same.settleCount(on: .startsIn)
        #expect(!unchanged)
        let set = try #require(Self.started(Self.workout()).currentSet)
        var held = WorkoutPhase.held(set)
        let midSequence = held.settleCount(on: .startsIn)
        #expect(!midSequence)
        #expect(held == .held(set))
    }

    @Test("A count's set changed to reps and back opens on Starts in, not its old count")
    func timedAgain() throws {
        var workout = try Self.workout()
        let live = Self.started(workout)
        workout.exercises[0].plan.target = .reps(10)
        let asReps = LiveWorkout(workout: workout, loggedWorkout: live.loggedWorkout)
            .beginningCount(at: Self.at(60))
        #expect(asReps.count == nil)
        workout.exercises[0].plan.target = .time(seconds: 30)
        let again = LiveWorkout(workout: workout, loggedWorkout: asReps)
            .beginningCount(at: Self.at(60))
        #expect(again.count?.startClock == 70)
    }

    @Test("A reps set logs as before, and begins no count")
    func reps() throws {
        let workout = try Workout(exercises: [WorkoutExercise.builtIn("Push-up") { $0.sets = 2 }])
        let live = Self.started(workout)
        #expect(live.loggedWorkout.count == nil)
        let after = try Self.logged(live, at: 5)
        let first = after.loggedWorkout.sets.first
        #expect(first?.target == first?.plannedTarget)
        #expect(after.loggedWorkout.count == nil)
    }
}
