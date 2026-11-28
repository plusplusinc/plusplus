import Foundation
import Testing
@testable import WorkoutStore

/// A timed set's count on the workout's clock: when it begins, "Start in", the time done at a
/// log, +15 s, the rest after it, and a count that ran out while the app was away.
@Suite("Timed set")
struct TimedSetTests {
    static let start = Date(timeIntervalSinceReferenceDate: 1000)
    /// From a count's "Start in" to its set's start: its length and its hold at 0:00.
    static let lead = Double(LiveWorkout.startIn) + LiveWorkout.startInHold

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

    /// `workout` as Start begins it, at `start`, with its first count's start put at 10 on the
    /// clock, whatever "Start in" is: the tests of a count's own arithmetic read one timeline,
    /// and `startIn()` checks the lead Start begins.
    static func started(_ workout: Workout) -> LiveWorkout {
        var begun = begun(workout)
        begun.loggedWorkout.count?.startClock = 10
        return begun
    }

    /// `workout` as Start begins it, at `start`, its first count as `beginningCount` begins it.
    static func begun(_ workout: Workout) -> LiveWorkout {
        let loggedWorkout = WorkoutSession(
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

    @Test("Start on a plank begins a count Start in and its 0:00 hold ahead; then 30 s left")
    func startIn() throws {
        let live = try Self.begun(Self.workout())
        let timed = try #require(live.timedSet)
        let lead = Self.lead
        #expect(timed.startClock == lead)
        // "Start in" reads 0:00 its hold ahead of the set, which hasn't begun.
        let zero = lead - LiveWorkout.startInHold
        #expect(timed.startIn(atClock: zero) == LiveWorkout.startInHold)
        #expect(live.countStage(at: Self.at(zero)) == .startIn)
        #expect(live.countStage(at: Self.at(lead - 2)) == .startIn)
        #expect(timed.startIn(atClock: lead - 2) == 2)
        #expect(live.countStage(at: Self.at(lead)) == .counting)
        #expect(timed.remaining(atClock: lead) == 30)
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
        // The rest after it begins on the clock's whole second at the log, never ahead of it,
        // so it turns over with the workout's time.
        #expect(after.loggedWorkout.sets.first?.clockWhenLogged == 22)
    }

    @Test("+15 s adds to this set only, never during Start in or once over")
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
    static func landed(_ live: LiveWorkout, at seconds: Double) -> LiveWorkout {
        LiveWorkout(workout: live.workout, loggedWorkout: live.beginningCount(at: at(seconds)))
    }

    @Test("A log begins no count: with no rest before it, Start in begins as the screen lands")
    func startInAtLanding() throws {
        let live = try Self.started(Self.workout())
        let after = try Self.logged(live, at: 40)
        #expect(after.loggedWorkout.count == nil)
        // Landed 0.75 s after the log: its Start in is all from there, on the clock's nearest
        // whole second, so it turns over with the workout's time.
        let lead = Self.lead
        let landed = Self.landed(after, at: 40.75)
        #expect(landed.timedSet?.startClock == 41 + lead)
        #expect(Self.landed(after, at: 41.4).timedSet?.startClock == 41 + lead)
    }

    @Test("A rest that just moved on starts the count there; while it runs or holds, none begins")
    func fromRest() throws {
        let live = try Self.started(Self.workout(rest: 20))
        let after = try Self.logged(live, at: 40)
        #expect(after.beginningCount(at: Self.at(50)) == after.loggedWorkout)
        // 0:00 at 60, held a moment.
        #expect(after.beginningCount(at: Self.at(60.5)) == after.loggedWorkout)
        let leave = 60 + LiveWorkout.restHold
        let begun = LiveWorkout(
            workout: after.workout,
            loggedWorkout: after.beginningCount(at: Self.at(leave + 0.5)),
        )
        #expect(begun.timedSet?.startClock == leave)
        #expect(begun.countStage(at: Self.at(leave + 0.5)) == .counting)
    }

    @Test("A rest that ended long ago opens on Start in from now")
    func afterAway() throws {
        let live = try Self.started(Self.workout(rest: 20))
        let after = try Self.logged(live, at: 40)
        let begun = LiveWorkout(
            workout: after.workout,
            loggedWorkout: after.beginningCount(at: Self.at(100)),
        )
        #expect(begun.timedSet?.startClock == 100 + Self.lead)
    }

    @Test("Between a set's sides, the right side gets a 5 s Start in as it shows")
    func sides() throws {
        var live = try Self.started(Self.workout())
        for second in [40.0, 80, 120] {
            live = try Self.landed(Self.logged(live, at: second), at: second)
        }
        #expect(live.currentSet?.side == .left)
        let left = try #require(live.timedSet)
        live = try Self.logged(live, at: left.endClock)
        #expect(live.currentSet?.side == .right)
        live = Self.landed(live, at: left.endClock + 0.4)
        let sideLead = Double(LiveWorkout.startInSides) + LiveWorkout.startInHold
        #expect(live.timedSet?.startClock == left.endClock + sideLead)
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
        #expect(caught.timedSet?.startClock == 300 + Self.lead)
    }

    @Test("A count begun for another set is none: the row changed to reps")
    func otherSet() throws {
        var live = try Self.started(Self.workout())
        live.workout.exercises[0].plan.target = .reps(10)
        #expect(live.timedSet == nil)
        #expect(live.countStage(at: Self.at(20)) == nil)
    }

    @Test("A timed set an edit makes current mid-count opens on Start in from the edit")
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
        #expect(begun.timedSet?.startClock == 20 + Self.lead)
        #expect(begun.countStage(at: Self.at(20)) == .startIn)
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
        let ontoCount = running.settleCount(on: .startIn)
        #expect(ontoCount)
        #expect(running == .timing(.startIn))
        var timing = WorkoutPhase.timing(.counting)
        let offCount = timing.settleCount(on: nil)
        #expect(offCount, "The row changed to reps")
        #expect(timing == .running)
        var same = WorkoutPhase.timing(.startIn)
        let unchanged = same.settleCount(on: .startIn)
        #expect(!unchanged)
        let set = try #require(Self.started(Self.workout()).currentSet)
        var held = WorkoutPhase.held(set)
        let midSequence = held.settleCount(on: .startIn)
        #expect(!midSequence)
        #expect(held == .held(set))
    }

    @Test("A count's set changed to reps and back opens on Start in from each change")
    func timedAgain() throws {
        var live = try Self.started(Self.workout())
        let lead = Self.lead
        for (target, at) in [(SetTarget.reps(10), 60.0), (.time(seconds: 30), 62)] {
            var edited = live.workout
            edited.exercises[0].plan.target = target
            live = LiveWorkout(workout: edited, loggedWorkout: live.droppingCount(for: edited))
            live = LiveWorkout(workout: edited, loggedWorkout: live.beginningCount(at: Self.at(at)))
            #expect(live.loggedWorkout.count?.startClock == at + lead, "as \(target)")
        }
    }
}
