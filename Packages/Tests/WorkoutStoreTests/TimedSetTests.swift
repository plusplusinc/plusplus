import Foundation
import Testing
@testable import WorkoutStore

/// A timed set's count on the workout's clock: when it begins, "Starts in", the time done at a
/// log, +15 s, the rest after it, and a count that ran out while the app was away.
@Suite("Timed set")
struct TimedSetTests {
    private static let start = Date(timeIntervalSinceReferenceDate: 1000)

    /// `start` plus `seconds`.
    private static func at(_ seconds: Double) -> Date {
        start.addingTimeInterval(seconds)
    }

    /// A plank, 3 × 30 s resting `rest` s between sets, then a side plank, 1 × 20 s per side,
    /// then push-ups.
    private static func routine(rest: Int = 0) throws -> Routine {
        var plank = try RoutineExercise.builtIn("Plank") { $0.sets = 3 }
        plank.plan.target = .time(seconds: 30)
        plank.setRest(rest)
        var side = try RoutineExercise.builtIn("Side plank") { $0.sets = 1 }
        side.plan.target = .time(seconds: 20)
        side.setRest(0)
        let push = try RoutineExercise.builtIn("Push-up") { $0.sets = 1 }
        return Routine(exercises: [plank, side, push])
    }

    /// The workout as Start begins it on `routine`, at `start`.
    private static func started(_ routine: Routine) -> LiveWorkout {
        let workout = Workout(routineID: routine.id, routineName: "Test", startedAt: start)
        let begun = LiveWorkout(routine: routine, workout: workout).beginningCount(at: start)
        return LiveWorkout(routine: routine, workout: begun)
    }

    /// `live` with its current set logged at `seconds`.
    private static func logged(_ live: LiveWorkout, at seconds: Double) throws -> LiveWorkout {
        let set = try #require(live.currentSet)
        let row = try #require(live.currentExercise)
        return LiveWorkout(
            routine: live.routine,
            workout: live.logging(set, of: row, at: at(seconds)),
        )
    }

    @Test("Start on a plank begins a count 10 s ahead; at 10 s it counts, 30 s left")
    func startsIn() throws {
        let live = try Self.started(Self.routine())
        let timed = try #require(live.timedSet)
        #expect(timed.startClock == 10)
        #expect(live.countStage(at: Self.at(3)) == .startsIn)
        #expect(timed.startsIn(atClock: 3) == 7)
        #expect(live.countStage(at: Self.at(10)) == .counting)
        #expect(timed.remaining(atClock: 10) == 30)
    }

    @Test("Start now moves the count's start to now; once the set counts it changes nothing")
    func startNow() throws {
        let live = try Self.started(Self.routine())
        let now = LiveWorkout(routine: live.routine, workout: live.startingCountNow(at: Self.at(4)))
        #expect(now.timedSet?.startClock == 4)
        let counting = now.startingCountNow(at: Self.at(6))
        #expect(counting == now.workout)
    }

    @Test("At zero the set logs its full time, its clock the count's end, however late")
    func runOut() throws {
        let live = try Self.started(Self.routine(rest: 60))
        let after = try Self.logged(live, at: 45)
        let set = try #require(after.workout.sets.first)
        #expect(set.target == .time(seconds: 30))
        #expect(set.plannedTarget == .time(seconds: 30))
        #expect(set.clockWhenLogged == 40)
        #expect(after.rest()?.startClock == 40)
        // The rest still runs: no count begins.
        #expect(after.workout.count == nil)
    }

    @Test("A log with 17 to 18 s left stores 12 done of 30")
    func earlyLog() throws {
        let live = try Self.started(Self.routine())
        let after = try Self.logged(live, at: 10 + 12.5)
        #expect(after.workout.sets.first?.target == .time(seconds: 12))
        #expect(after.workout.sets.first?.clockWhenLogged == 22.5)
    }

    @Test("+15 s adds to this set only, never during Starts in or once over")
    func extend() throws {
        let live = try Self.started(Self.routine())
        #expect(live.extendingCount(by: 15, at: Self.at(5)) == live.workout)
        let extended = LiveWorkout(
            routine: live.routine,
            workout: live.extendingCount(by: 15, at: Self.at(30)),
        )
        #expect(extended.timedSet?.length == 45)
        #expect(extended.timedSet?.remaining(atClock: 30) == 25)
        #expect(extended.extendingCount(by: 15, at: Self.at(55)) == extended.workout)
        let after = try Self.logged(extended, at: 55)
        #expect(after.workout.sets.first?.target == .time(seconds: 45))
        #expect(after.workout.sets.first?.timeAdded == 15)
        #expect(Self.landed(after, at: 56).timedSet?.length == 30)
    }

    /// `live` as the screen lands on its current set at `seconds`, beginning its count.
    private static func landed(_ live: LiveWorkout, at seconds: Double) -> LiveWorkout {
        LiveWorkout(routine: live.routine, workout: live.beginningCount(at: at(seconds)))
    }

    @Test("A log begins no count: with no rest before it, Starts in begins as the screen lands")
    func startsInAtLanding() throws {
        let live = try Self.started(Self.routine())
        let after = try Self.logged(live, at: 40)
        #expect(after.workout.count == nil)
        // Landed 0.75 s after the log: its ten seconds are all from there.
        let landed = Self.landed(after, at: 40.75)
        #expect(landed.timedSet?.startClock == 50.75)
        #expect(landed.timedSet?.startsIn(atClock: 40.75) == 10)
    }

    @Test("A skipped rest ends now: the timed set next counts from the tap")
    func restSkipped() throws {
        let live = try Self.started(Self.routine(rest: 30))
        let after = try Self.logged(live, at: 45)
        // The rest runs from 40 to 70; skipped at 63.
        let cut = LiveWorkout(
            routine: after.routine,
            workout: after.skippingRest(at: Self.at(63)),
        )
        let timed = try #require(cut.timedSet, "Begun at the tap, not at the rest's end")
        #expect(timed.startClock == 63)
        #expect(cut.countStage(at: Self.at(63)) == .counting)
        // The screen's own begin, as the rest ends, changes nothing.
        #expect(cut.beginningCount(at: Self.at(63.1)) == cut.workout)
    }

    @Test("A rest that just ended starts the count at its end; while it runs, none begins")
    func fromRest() throws {
        let live = try Self.started(Self.routine(rest: 20))
        let after = try Self.logged(live, at: 40)
        #expect(after.beginningCount(at: Self.at(50)) == after.workout)
        let begun = LiveWorkout(
            routine: after.routine,
            workout: after.beginningCount(at: Self.at(60.5)),
        )
        #expect(begun.timedSet?.startClock == 60)
        #expect(begun.countStage(at: Self.at(60.5)) == .counting)
    }

    @Test("A rest that ended long ago opens on Starts in from now")
    func afterAway() throws {
        let live = try Self.started(Self.routine(rest: 20))
        let after = try Self.logged(live, at: 40)
        let begun = LiveWorkout(
            routine: after.routine,
            workout: after.beginningCount(at: Self.at(100)),
        )
        #expect(begun.timedSet?.startClock == 110)
    }

    @Test("Between a set's sides, the right side gets Starts in as it shows")
    func sides() throws {
        var live = try Self.started(Self.routine())
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
        let live = try Self.started(Self.routine())
        let paused = live.workout.pausing(at: Self.at(20)).resuming(at: Self.at(80))
        let resumed = LiveWorkout(routine: live.routine, workout: paused)
        #expect(resumed.timedSet?.remaining(atClock: paused.clock(at: Self.at(80))) == 20)
    }

    @Test("A count over at launch logs at full time, once; the next set's begins from now")
    func caughtUp() throws {
        let live = try Self.started(Self.routine())
        let caught = LiveWorkout(routine: live.routine, workout: live.caughtUp(at: Self.at(300)))
        #expect(caught.workout.sets.count == 1)
        #expect(caught.workout.sets.first?.clockWhenLogged == 40)
        #expect(caught.timedSet?.startClock == 310)
    }

    @Test("A count begun for another set is none: the row changed to reps")
    func otherSet() throws {
        var live = try Self.started(Self.routine())
        live.routine.exercises[0].plan.target = .reps(10)
        #expect(live.timedSet == nil)
        #expect(live.countStage(at: Self.at(20)) == nil)
    }

    @Test("A timed set an edit makes current mid-count opens on Starts in from the edit")
    func editMakesCurrent() throws {
        var live = try Self.started(Self.routine())
        // The plank counts from 10; at 20 a side plank is moved ahead of it.
        let side = live.routine.exercises.remove(at: 1)
        live.routine.exercises.insert(side, at: 0)
        #expect(live.timedSet == nil, "The plank's count stays with the plank")
        let begun = LiveWorkout(
            routine: live.routine,
            workout: live.beginningCount(at: Self.at(20)),
        )
        #expect(begun.currentSet?.row == side.id)
        #expect(begun.timedSet?.startClock == 30)
        #expect(begun.countStage(at: Self.at(20)) == .startsIn)
    }

    @Test("A time changed mid-count keeps its start; cut below the time done, it logs that time")
    func timeChangedMidCount() throws {
        var live = try Self.started(Self.routine())
        // Counting from 10; at 15, 5 s done, 25 left.
        live.routine.exercises[0].plan.target = .time(seconds: 20)
        let longer = try #require(live.timedSet)
        #expect(longer.startClock == 10)
        #expect(longer.remaining(atClock: 15) == 15)
        #expect(live.beginningCount(at: Self.at(15)) == live.workout, "No second count begins")
        live.routine.exercises[0].plan.target = .time(seconds: 3)
        let shorter = try #require(live.timedSet)
        #expect(shorter.isOver(atClock: 15))
        let after = try Self.logged(live, at: 15)
        let set = try #require(after.workout.sets.first)
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
        let set = try #require(Self.started(Self.routine()).currentSet)
        var held = WorkoutPhase.held(set)
        let midSequence = held.settleCount(on: .startsIn)
        #expect(!midSequence)
        #expect(held == .held(set))
    }

    @Test("A count's set changed to reps and back opens on Starts in, not its old count")
    func timedAgain() throws {
        var routine = try Self.routine()
        let live = Self.started(routine)
        routine.exercises[0].plan.target = .reps(10)
        let asReps = LiveWorkout(routine: routine, workout: live.workout)
            .beginningCount(at: Self.at(60))
        #expect(asReps.count == nil)
        routine.exercises[0].plan.target = .time(seconds: 30)
        let again = LiveWorkout(routine: routine, workout: asReps)
            .beginningCount(at: Self.at(60))
        #expect(again.count?.startClock == 70)
    }

    @Test("A workout finished mid-count keeps no count")
    func finishedMidCount() throws {
        let live = try Self.started(Self.routine())
        #expect(live.workout.count != nil)
        #expect(live.workout.finishing(at: Self.at(15)).count == nil)
    }

    @Test("A reps set logs as before, and begins no count")
    func reps() throws {
        let routine = try Routine(exercises: [RoutineExercise.builtIn("Push-up") { $0.sets = 2 }])
        let live = Self.started(routine)
        #expect(live.workout.count == nil)
        let after = try Self.logged(live, at: 5)
        #expect(after.workout.sets.first?.target == after.workout.sets.first?.plannedTarget)
        #expect(after.workout.count == nil)
    }
}
