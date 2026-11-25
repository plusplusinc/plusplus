import Foundation
import Testing
@testable import WorkoutStore

/// The situation a workout derives at a moment, pinned against what today's code says of the
/// same moment: the phase a screen opening then takes (`WorkoutPhase(resuming:)`) and the
/// count's stage (`LiveWorkout.countStage(at:)`). Where those two, or another rule, give a
/// second answer, the test names the one the situation takes.
@Suite("Workout situation")
struct WorkoutSituationTests {
    static let start = Date(timeIntervalSinceReferenceDate: 1000)

    /// Push-ups, 2 sets resting 60 s, between them and before what follows; then a plank,
    /// 2 × 30 s resting `plankRest` s between sets.
    static func workout(plankRest: Int = 0) throws -> Workout {
        var push = try WorkoutExercise.builtIn("Push-up") { $0.sets = 2 }
        push.setRest(60)
        var plank = try WorkoutExercise.builtIn("Plank") { $0.sets = 2 }
        plank.plan.target = .time(seconds: 30)
        plank.setRest(plankRest)
        return Workout(exercises: [push, plank])
    }

    /// `workout` as Start stores it at `start`: nothing begun, the screen not yet on its set.
    static func started(_ workout: Workout) -> LiveWorkout {
        LiveWorkout(
            workout: workout,
            loggedWorkout: LoggedWorkout(
                workoutID: workout.id,
                workoutName: "Test",
                startedAt: start,
            ),
        )
    }

    /// The situation at `now`, with the set it names checked against the current set.
    static func situation(_ live: LiveWorkout, at now: Date) -> WorkoutSituation {
        let situation = live.situation(at: now)
        switch situation {
        case let .comingUp(set), let .doing(set, _):
            #expect(set == live.currentSet)
        case let .countingIn(count):
            #expect(count.set == live.currentSet)
        case let .resting(rest):
            #expect(rest.next == live.currentSet)
        case .notStarted, .allLogged, .nothingToDo:
            #expect(live.currentSet == nil || !live.loggedWorkout.isInProgress)
        }
        return situation
    }

    /// Expects today's code to say of `now` what `situation` does: "Start in" for a count
    /// running in, a timed set's count for one counting, at rest on a set with no count for a
    /// reps set up, and a screen opening in the rest for one running.
    static func expectAgrees(_ live: LiveWorkout, at now: Date) {
        let phase = WorkoutPhase(resuming: live, at: now)
        let stage = live.countStage(at: now)
        switch situation(live, at: now) {
        case .countingIn:
            #expect(phase == .timing(.startIn) && stage == .startIn)
        case .doing(_, .some):
            #expect(phase == .timing(.counting) && stage == .counting)
        case .doing(_, nil):
            #expect(phase == .running && stage == nil)
        case let .resting(rest):
            #expect(phase.resting?.set == rest.after && phase.resting?.beat == .settled)
            #expect(stage == nil)
        case let other:
            Issue.record("\(other) is pinned by its own test")
        }
    }

    @Test("Through a workout, each situation is the phase a screen opens on and the count's stage")
    func agreesWithToday() throws {
        var live = try Self.started(Self.workout(plankRest: 60))
        live.loggedWorkout = live.landingStart(at: Self.at(0.5))
        Self.expectAgrees(live, at: Self.at(1))
        #expect(try Self.situation(live, at: Self.at(1)) == .countingIn(#require(live.setCount)))
        let up = live.at(clock: 1)
        Self.expectAgrees(live, at: up)
        #expect(try Self.situation(live, at: up) == .doing(#require(live.currentSet), nil))

        // Into the rest between push-ups, and out of it onto the second, which has no count due.
        live = try live.logging(at: live.at(clock: 10))
        Self.expectAgrees(live, at: live.at(clock: 30))
        let leave = try #require(live.rest()?.leaveClock)
        Self.expectAgrees(live, at: live.at(clock: leave))
        #expect(try Self.situation(live, at: live.at(clock: leave)) == .doing(
            #require(live.currentSet),
            nil,
        ))

        // Into the rest before the plank; its end noticed at once begins its "Start in".
        live = try live.logging(at: live.at(clock: 80))
        Self.expectAgrees(live, at: live.at(clock: 100))
        let toPlank = try #require(live.rest()?.leaveClock)
        live = live.countBegun(at: live.at(clock: toPlank + 0.5))
        Self.expectAgrees(live, at: live.at(clock: toPlank + 1))
        let timed = try #require(live.timedSet)
        Self.expectAgrees(live, at: live.at(clock: timed.startClock + 1))
        #expect(Self.situation(live, at: live.at(clock: timed.startClock + 1)) == .doing(
            timed.set,
            timed,
        ))
        // Run out with nobody watching, it is still the set being done until a screen logs it,
        // as the count's stage and a screen opening then say (`caughtUp`).
        Self.expectAgrees(live, at: live.at(clock: timed.endClock + 5))

        // Logged early, a rest; its end noticed within a second: the next plank counts from the
        // rest's move on, with none due before it.
        live = try live.logging(at: live.at(clock: timed.startClock + 10))
        Self.expectAgrees(live, at: live.at(clock: timed.startClock + 30))
        let between = try #require(live.rest()?.leaveClock)
        live = live.countBegun(at: live.at(clock: between + 0.9))
        #expect(live.timedSet?.startClock == between)
        Self.expectAgrees(live, at: live.at(clock: between + 0.9))
    }

    @Test("""
    A count due and not yet begun is coming up; today a screen opening then is at rest on the \
    set, while the count's rule still owes it
    """)
    func comingUp() throws {
        /// Two answers today: the phase says at rest on the set (`.running`, the key would take
        /// a log), and `beginningCount` begins a count for it. The situation takes the second:
        /// the count is what the stored workout is waiting for, and it is begun as the screen
        /// lands on the set, so all of it is seen.
        func expectComingUp(_ live: LiveWorkout, at now: Date) throws {
            let set = try #require(live.currentSet)
            #expect(Self.situation(live, at: now) == .comingUp(set))
            #expect(WorkoutPhase(resuming: live, at: now) == .running)
            #expect(live.countStage(at: now) == nil)
            #expect(live.beginningCount(at: now).count?.set == set, "A count is owed")
        }
        var live = try Self.started(Self.workout(plankRest: 0))
        // After Start, before the screen lands on the first set.
        try expectComingUp(live, at: Self.at(0.3))

        // Out of a rest before another exercise, its end not yet noticed.
        live.loggedWorkout = live.landingStart(at: Self.at(0.5))
        live = try live.logging(at: live.at(clock: 10))
        live = try live.logging(at: live.at(clock: 80))
        let toPlank = try #require(live.rest()?.leaveClock)
        try expectComingUp(live, at: live.at(clock: toPlank + 5))

        // After a timed set's log with no rest, before its next set: a timed set always opens on
        // a count.
        live = live.countBegun(at: live.at(clock: toPlank))
        let timed = try #require(live.timedSet)
        live = try live.logging(at: live.at(clock: timed.startClock + 10))
        #expect(live.rest() == nil)
        try expectComingUp(live, at: live.at(clock: timed.startClock + 10.2))
    }

    @Test("""
    Skip rest's count for the next set reads as the rest until it moves on, though the count's \
    stage already says Start in
    """)
    func skippedRestCounts() throws {
        // Two answers today: `countStage` reads the count Skip rest begun as "Start in" from the
        // tap, and a screen opening in its hold opens in the rest. The situation takes the rest:
        // the count's "Start in" begins only as the rest moves on (`WorkoutRest.leaveClock`).
        var live = try Self.started(Self.workout())
        live.loggedWorkout = live.landingStart(at: Self.at(0.5))
        live = try live.logging(at: live.at(clock: 10))
        live = try live.logging(at: live.at(clock: 80))
        let tap = 100.0
        live.loggedWorkout = live.skippingRest(at: live.at(clock: tap))
        let inHold = live.at(clock: tap + 0.1)
        #expect(live.countStage(at: inHold) == .startIn)
        #expect(WorkoutPhase(resuming: live, at: inHold).resting != nil)
        #expect(try Self.situation(live, at: inHold) == .resting(#require(live.rest())))
        let moved = live.at(clock: tap + LiveWorkout.skipHold)
        Self.expectAgrees(live, at: moved)
        #expect(try Self.situation(live, at: moved) == .countingIn(#require(live.setCount)))
    }

    @Test("""
    A skipped rest before the same exercise's reps set runs to its stored leave, as a screen \
    opening then finds it
    """)
    func skippedRestBetweenSets() throws {
        // Two answers today: the screen that took the tap moves on `skipHold` after it, by the
        // time its phase keeps (`Resting.skipLeave`); the stored rest, cut to whole seconds
        // rounded down, moves on at its own hold. The situation can read only the stored one.
        var live = try Self.started(Self.workout())
        live.loggedWorkout = live.landingStart(at: Self.at(0.5))
        live = try live.logging(at: live.at(clock: 10))
        live.loggedWorkout = live.skippingRest(at: live.at(clock: 30.6))
        let leave = try #require(live.rest()?.leaveClock)
        #expect(leave > 30.6 + LiveWorkout.skipHold)
        Self.expectAgrees(live, at: live.at(clock: 30.6 + LiveWorkout.skipHold))
        #expect(try Self.situation(live, at: live.at(clock: leave - 0.1)) == .resting(
            #require(live.rest()),
        ))
        Self.expectAgrees(live, at: live.at(clock: leave))
    }

    @Test("""
    A rest running toward a row moved above it still rests, where a screen opening today is at \
    rest on that row's set
    """)
    func restTowardRowMovedAbove() throws {
        // Two answers today: `WorkoutPhase(resuming:)` opens at rest on the set, since a move
        // back up to a row not in a superset rests nowhere (`rests(after:leadingTo:)`), while
        // `rest()` still runs the rest after the last set, and `beginningCount` waits for it.
        // The situation takes the rest: every stored rule (the count's, +15 s's, Skip rest's)
        // acts on it.
        var live = try Self.started(Self.workout())
        live.loggedWorkout = live.landingStart(at: Self.at(0.5))
        live = try live.logging(at: live.at(clock: 10))
        live = try live.logging(at: live.at(clock: 80))
        live.workout.exercises.reverse()
        let now = live.at(clock: 100)
        let rest = try #require(live.rest())
        #expect(rest.next.row == live.workout.exercises[0].id)
        #expect(WorkoutPhase(resuming: live, at: now) == .running)
        #expect(live.beginningCount(at: now) == live.loggedWorkout, "No count begun mid-rest")
        #expect(Self.situation(live, at: now) == .resting(rest))
    }

    @Test("""
    Every set logged is all logged, a workout with no rows nothing to do, and a finished one not \
    started; today's phase reads each as at rest, or idle with no workout
    """)
    func withNoSet() throws {
        // Two answers today for the first two: the phase says at rest (`.running`), and
        // `isDone` says done. The situation takes `isDone`: there is no set to be at rest on.
        var live = try Self.started(Self.workout(plankRest: 0))
        live.loggedWorkout = live.landingStart(at: Self.at(0.5))
        for index in live.workout.setOrder.indices {
            live = try live.logging(at: live.at(clock: Double(index + 1) * 100))
        }
        let now = live.at(clock: 500)
        #expect(live.isDone)
        #expect(WorkoutPhase(resuming: live, at: now) == .running)
        #expect(Self.situation(live, at: now) == .allLogged)

        var emptied = live
        emptied.workout.exercises.removeAll()
        #expect(WorkoutPhase(resuming: emptied, at: now) == .running)
        #expect(Self.situation(emptied, at: now) == .nothingToDo)

        var finished = live
        finished.loggedWorkout = live.finishing(at: now)
        #expect(Self.situation(finished, at: now.addingTimeInterval(60)) == .notStarted)
    }

    @Test("Paused in any situation, it holds as time passes, and resumed it goes on from there")
    func pausedHolds() throws {
        var live = try Self.started(Self.workout(plankRest: 60))
        live.loggedWorkout = live.landingStart(at: Self.at(0.5))
        var moments: [(LiveWorkout, Double)] = [(live, -2), (live, 1)]
        live = try live.logging(at: live.at(clock: 10))
        moments.append((live, 30))
        live = try live.logging(at: live.at(clock: 80))
        let toPlank = try #require(live.rest()?.leaveClock)
        moments.append((live, toPlank + 3))
        live = live.countBegun(at: live.at(clock: toPlank))
        moments.append((live, toPlank + 3))
        moments.append((live, toPlank + 10))
        for (live, clock) in moments {
            let pausedAt = live.at(clock: clock)
            let before = live.situation(at: pausedAt)
            var paused = live
            paused.loggedWorkout = live.loggedWorkout.pausing(at: pausedAt)
            let away = pausedAt.addingTimeInterval(1000)
            #expect(paused.situation(at: away) == before, "Paused at \(clock): \(before)")
            var resumed = paused
            resumed.loggedWorkout = paused.loggedWorkout.resuming(at: away)
            #expect(resumed.situation(at: away.addingTimeInterval(2)) == live
                .situation(at: pausedAt.addingTimeInterval(2)))
        }
    }

    static func at(_ seconds: Double) -> Date {
        start.addingTimeInterval(seconds)
    }
}

extension LiveWorkout {
    /// When the workout's clock reads `clock`, running on with no pause.
    fileprivate func at(clock: Double) -> Date {
        loggedWorkout.date(ofClock: clock)
    }

    /// The workout with its current set logged at `now`.
    fileprivate func logging(at now: Date) throws -> Self {
        let set = try #require(currentSet)
        let row = try #require(currentExercise)
        return Self(workout: workout, loggedWorkout: logging(set, of: row, at: now))
    }

    /// The workout with the current set's count begun at `now`, as the screen begins it.
    fileprivate func countBegun(at now: Date) -> Self {
        Self(workout: workout, loggedWorkout: beginningCount(at: now))
    }
}
