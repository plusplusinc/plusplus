import Foundation
import Testing
@testable import WorkoutStore

/// Which rest follows each set of a workout, how long is left of it at a moment on the workout's
/// clock, and where a screen opening on a workout mid-rest is.
@Suite("Workout rest")
struct WorkoutRestTests {
    private static let start = Date(timeIntervalSinceReferenceDate: 1000)

    /// `start` plus `seconds`.
    private static func at(_ seconds: Double) -> Date {
        start.addingTimeInterval(seconds)
    }

    /// Bench press, 3 sets resting 90 s, then a per-side Bulgarian split squat, 2 sets resting
    /// 60 s, then push-ups, 1 set resting 45 s.
    private static func plain() throws -> Workout {
        var bench = try WorkoutExercise.builtIn("Barbell bench press") { $0.sets = 3 }
        bench.setRest(90)
        var split = try WorkoutExercise.builtIn("Bulgarian split squat") { $0.sets = 2 }
        split.setRest(60)
        var push = try WorkoutExercise.builtIn("Push-up") { $0.sets = 1 }
        push.setRest(45)
        return Workout(exercises: [bench, split, push])
    }

    /// A superset of dumbbell bench press and pull-up, 2 rounds resting `round` s after each,
    /// then a plank.
    private static func superset(round: Int = 75) throws -> Workout {
        var workout = try Workout(exercises: [
            WorkoutExercise.builtIn("Dumbbell bench press") { $0.sets = 2 },
            WorkoutExercise.builtIn("Pull-up") { $0.sets = 2 },
            WorkoutExercise.builtIn("Push-up") { $0.sets = 1 },
        ])
        workout.join(workout.exercises[0].id, .below)
        workout.setRestAfterRound(round, of: workout.exercises[0].id)
        return workout
    }

    /// `workout` in progress with its first `count` sets logged, each `every` seconds after
    /// the last, from the start.
    private static func live(
        _ workout: Workout,
        logged count: Int,
        every: Double = 10,
    ) throws -> LiveWorkout {
        var loggedWorkout = WorkoutSession(
            workoutID: workout.id,
            workoutName: "Test",
            startedAt: start,
        )
        for (index, set) in workout.setOrder.prefix(count).enumerated() {
            let row = try #require(workout.exercises.first { $0.id == set.row })
            loggedWorkout = loggedWorkout.logging(set, of: row, at: at(Double(index + 1) * every))
        }
        return LiveWorkout(workout: workout, loggedWorkout: loggedWorkout)
    }

    /// The rest between each set of `workout` and the next, in order, as the workout stores it.
    private static func rests(_ workout: Workout) -> [Int] {
        let order = workout.setOrder
        return order.indices.map { index in
            workout.rest(
                after: order[index],
                before: order.indices.contains(index + 1)
                    ? order[index + 1] : nil,
            )
        }
    }

    @Test("A plain row rests its own rest after each set; one per side, after each pair of sides")
    func plainAndSides() throws {
        // Bench 1, 2, 3, split 1L, 1R, 2L, 2R, push 1: none after the workout's last set.
        #expect(try Self.rests(Self.plain()) == [90, 90, 90, 0, 60, 0, 60, 0])
    }

    @Test("A superset rests after each round, none between its members; none after the last set")
    func supersetRounds() throws {
        // Bench 1, pull 1, bench 2, pull 2, push 1.
        #expect(try Self.rests(Self.superset()) == [0, 75, 0, 75, 0])
    }

    @Test("A rest of 0 runs no rest: none between sets, after a round, or before the next row")
    func restOfZero() throws {
        var workout = try Self.plain()
        workout.exercises[0].setRest(0)
        #expect(workout.restBetweenSets(of: workout.exercises[0].id) == nil)
        let live = try Self.live(workout, logged: 1)
        #expect(live.rest() == nil)
        #expect(!live.rests(after: live.loggedWorkout.sets[0].planned, leadingTo: .nextSet))
        let round = try Self.live(Self.superset(round: 0), logged: 2)
        let step = round.hiding([round.loggedWorkout.sets[1].planned])
            .step(logging: round.loggedWorkout.sets[1].planned)
        #expect(round.rest() == nil)
        #expect(!round.rests(after: round.loggedWorkout.sets[1].planned, leadingTo: step))
    }

    @Test("A log rests where a rest follows it: between sets, down the rail, back up a round")
    func logRests() throws {
        func rests(_ live: LiveWorkout) -> Bool {
            let last = live.loggedWorkout.sets[live.loggedWorkout.sets.count - 1].planned
            return live.rests(after: last, leadingTo: live.hiding([last]).step(logging: last))
        }
        let plain = try Self.plain()
        // After bench 1, its next set; after bench 3, on to the split squat; after its left
        // side, none; after its right, its next set; after the last set, none.
        #expect(try [1, 3, 4, 5, 8].map { try rests(Self.live(plain, logged: $0)) }
            == [true, true, false, true, false])
        // After the round's first member, none; after its last, back up to the first; after the
        // last round, on to the next row.
        let superset = try Self.superset()
        #expect(try [1, 2, 4].map { try rests(Self.live(superset, logged: $0)) }
            == [false, true, true])
    }

    @Test("The time left runs on the workout's clock from the log; it holds 0:00, then is over")
    func timeLeft() throws {
        let live = try Self.live(Self.plain(), logged: 1)
        let rest = try #require(live.rest())
        #expect(rest.length == 90)
        // Logged 10 s in: 85 s left at 15 s, as a return from the background reads it.
        #expect(rest.remaining(atClock: live.loggedWorkout.clock(at: Self.at(15))) == 85)
        // 0:00 at 100, held there before the screen moves on.
        #expect(rest.remaining(atClock: live.loggedWorkout.clock(at: Self.at(100))) == 0)
        #expect(!rest.isOver(atClock: live.loggedWorkout.clock(at: Self.at(100))))
        let leave = 100 + LiveWorkout.restHold
        #expect(rest.leaveClock == live.loggedWorkout.clock(at: Self.at(leave)))
        #expect(!rest.isOver(atClock: live.loggedWorkout.clock(at: Self.at(leave - 0.01))))
        #expect(rest.isOver(atClock: live.loggedWorkout.clock(at: Self.at(leave))))
        #expect(rest.remaining(atClock: live.loggedWorkout.clock(at: Self.at(500))) == 0)
    }

    @Test("A pause stops the rest's time; a resume carries on from where it stopped")
    func pauseAndResume() throws {
        var live = try Self.live(Self.plain(), logged: 1)
        let rest = try #require(live.rest())
        live.loggedWorkout = live.loggedWorkout.pausing(at: Self.at(40))
        #expect(rest.remaining(atClock: live.loggedWorkout.clock(at: Self.at(40))) == 60)
        #expect(rest.remaining(atClock: live.loggedWorkout.clock(at: Self.at(400))) == 60)
        live.loggedWorkout = live.loggedWorkout.resuming(at: Self.at(400))
        #expect(rest.remaining(atClock: live.loggedWorkout.clock(at: Self.at(410))) == 50)
    }

    @Test(
        "+15 s adds 15 seconds, twice 30; Skip rest stores its tap, holds its time, then moves on",
    )
    func plusAndSkip() throws {
        var live = try Self.live(Self.plain(), logged: 1)
        live.loggedWorkout = live.extendingRest(by: 15, at: Self.at(20))
        #expect(live.rest()?.length == 105)
        live.loggedWorkout = live.extendingRest(by: 15, at: Self.at(25))
        #expect(live.rest()?.length == 120)
        // Logged at 10 s, skipped 70.6 s into its rest, a reps set of the same exercise next,
        // with no count stored: the rest keeps its length, and moves on `skipHold` after the tap.
        live.loggedWorkout = live.skippingRest(at: Self.at(80.6))
        #expect(live.loggedWorkout.count == nil)
        let ended = try #require(live.rest())
        let tap = live.loggedWorkout.clock(at: Self.at(80.6))
        #expect(ended.length == 120)
        #expect(ended.skippedAt == tap)
        #expect(ended.leaveClock == tap + LiveWorkout.skipHold)
        #expect(!ended.isOver(atClock: tap + LiveWorkout.skipHold - 0.01))
        #expect(ended.isOver(atClock: tap + LiveWorkout.skipHold))
        // Its count shows the 49.4 s it had at the tap, the same at every later moment.
        for later in [tap, tap + 0.1, tap + 30] {
            #expect(abs(ended.shownLeft(atClock: later) - 49.4) < 1e-9)
        }
        // Skipped, a second Skip rest or +15 s changes nothing, through the hold and after.
        let skipped = live.loggedWorkout
        for second in [80.7, 81.2] {
            #expect(live.extendingRest(by: 15, at: Self.at(second)) == skipped)
            #expect(live.skippingRest(at: Self.at(second)) == skipped)
        }
    }

    @Test("A skip belongs to its own rest: the next rest, and a workout started again, run out")
    func skipStaysWithItsRest() throws {
        var live = try Self.live(Self.plain(), logged: 1)
        live.loggedWorkout = live.skippingRest(at: Self.at(30))
        #expect(live.rest()?.skippedAt != nil)
        let row = try #require(live.currentExercise)
        let next = try #require(live.currentSet)
        live.loggedWorkout = live.loggedWorkout.logging(next, of: row, at: Self.at(40))
        // Discarded and started again on the same screen, with a clock from 0 again.
        let again = try Self.live(Self.plain(), logged: 1)
        for rest in try [#require(live.rest()), #require(again.rest())] {
            #expect(rest.skippedAt == nil)
            #expect(rest.leaveClock == rest.endClock + LiveWorkout.restHold)
        }
    }

    @Test(
        "Drawn without the set just logged, the rest after that set is none, not the skip before",
    )
    func restAfterSetJustLogged() throws {
        var live = try Self.live(Self.plain(), logged: 1)
        live.loggedWorkout = live.skippingRest(at: Self.at(30))
        let row = try #require(live.currentExercise)
        let next = try #require(live.currentSet)
        live.loggedWorkout = live.loggedWorkout.logging(next, of: row, at: Self.at(40))
        let drawn = live.hiding([next])
        // The rest found without the set is the skipped one, still showing its time.
        let earlier = try #require(drawn.rest())
        #expect(earlier.shownLeft(atClock: drawn.loggedWorkout.clock(at: Self.at(40))) > 0)
        #expect(drawn.rest(after: next) == nil)
        #expect(try #require(live.rest(after: next)).skippedAt == nil)
    }

    @Test(
        "+15 s and Skip rest change nothing with no rest running: between a set's sides, or ended",
    )
    func plusWithNoRest() throws {
        // Bench press's 3 sets, then the split squat's first side: none between its sides.
        let sides = try Self.live(Self.plain(), logged: 4)
        #expect(sides.rest() == nil)
        #expect(sides.extendingRest(by: 15, at: Self.at(45)) == sides.loggedWorkout)
        #expect(sides.skippingRest(at: Self.at(45)) == sides.loggedWorkout)
        var ended = try Self.live(Self.plain(), logged: 1)
        ended.loggedWorkout = ended.loggedWorkout.finishing(at: Self.at(12))
        #expect(ended.extendingRest(by: 15, at: Self.at(13)) == ended.loggedWorkout)
        #expect(ended.skippingRest(at: Self.at(13)) == ended.loggedWorkout)
    }

    @Test("A screen opens in the rest running, settled: between sets, or between exercises")
    func opensInRest() throws {
        let between = try Self.live(Self.plain(), logged: 1)
        let within = WorkoutPhase(resuming: between, at: Self.at(30))
        #expect(within.resting?.isWithinExercise == true)
        #expect(within.resting?.beat == .settled)
        let down = try WorkoutPhase(resuming: Self.live(Self.plain(), logged: 3), at: Self.at(40))
        #expect(down.resting?.isWithinExercise == false)
        #expect(down.resting?.isBack == false)
        // After a superset's round with a round left, the rest above its first member.
        let round = try WorkoutPhase(
            resuming: Self.live(Self.superset(), logged: 2),
            at: Self.at(30),
        )
        #expect(round.resting?.isBack == true)
    }

    @Test("A screen opens on the next set once the rest has held 0:00, and idle with no workout")
    func opensAfterRest() throws {
        let live = try Self.live(Self.plain(), logged: 1)
        // 0:00 at 100: in its hold, the screen opens in the rest; then on the next set.
        #expect(WorkoutPhase(resuming: live, at: Self.at(100)).resting != nil)
        #expect(WorkoutPhase(resuming: live, at: Self.at(100 + LiveWorkout.restHold)) == .running)
        // Skipped at 40, it opens in the rest through the skip's hold, then on the next set, not
        // in the rest's 60 s left.
        var skipped = live
        skipped.loggedWorkout = live.skippingRest(at: Self.at(40))
        #expect(WorkoutPhase(resuming: skipped, at: Self.at(40.1)).resting != nil)
        #expect(WorkoutPhase(resuming: skipped, at: Self.at(40 + LiveWorkout.skipHold)) == .running)
        // Paused past its end on the wall clock, the rest still runs.
        var paused = live
        paused.loggedWorkout = paused.loggedWorkout.pausing(at: Self.at(20))
        #expect(WorkoutPhase(resuming: paused, at: Self.at(500)).resting != nil)
        // After a log with no rest after it, as a set's first side.
        #expect(try WorkoutPhase(resuming: Self.live(Self.plain(), logged: 4), at: Self.at(41))
            == .running)
        #expect(WorkoutPhase(resuming: nil, at: Self.at(0)) == .idle)
    }

    @Test("A set logged before its clock was kept rests for none")
    func noClockNoRest() throws {
        var live = try Self.live(Self.plain(), logged: 1)
        live.loggedWorkout.sets[0].clockWhenLogged = nil
        #expect(live.rest() == nil)
        #expect(WorkoutPhase(resuming: live, at: Self.at(11)) == .running)
    }
}
