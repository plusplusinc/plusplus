import Foundation
import Testing
@testable import WorkoutStore

/// The key at the bottom: what it says and what a tap on it does, one row per case, from the
/// workout as stored and as drawn, the phase, and where the current exercise is.
@Suite("What the workout key says and does")
struct WorkoutKeyTests {
    /// One case of the key: its inputs, the role and tap it should give, and whether Skip rest
    /// and +15 s change the rest.
    struct Row: CustomTestStringConvertible, Sendable {
        let name: String
        let key: WorkoutKey
        let role: WorkoutKey.Role
        let tap: WorkoutKey.Tap
        let takesRestTaps: Bool

        init(
            _ name: String,
            _ key: WorkoutKey,
            says role: WorkoutKey.Role,
            taps tap: WorkoutKey.Tap,
            takesRestTaps: Bool = false,
        ) {
            self.name = name
            self.key = key
            self.role = role
            self.tap = tap
            self.takesRestTaps = takesRestTaps
        }

        var testDescription: String {
            name
        }
    }

    /// Push-up, two sets; then Dumbbell row, one set, per side; and the workout's sets on it.
    struct Seed {
        let workout: Workout
        let push: WorkoutExercise
        let dumbbell: WorkoutExercise
        let first: PlannedSet
        let second: PlannedSet
        let left: PlannedSet
        let right: PlannedSet
        /// What logging Push-up's second set leads to: on down to the Dumbbell row's left.
        let toRow: LiveWorkout.Step

        init() throws {
            push = try WorkoutExercise.builtIn("Push-up") { $0.sets = 2 }
            dumbbell = try WorkoutExercise.builtIn("Dumbbell row") { $0.sets = 1 }
            workout = Workout(exercises: [push, dumbbell])
            first = PlannedSet(row: push.id, round: 1, side: nil)
            second = PlannedSet(row: push.id, round: 2, side: nil)
            left = PlannedSet(row: dumbbell.id, round: 1, side: .left)
            right = PlannedSet(row: dumbbell.id, round: 1, side: .right)
            toRow = .nextExercise(to: left, isBack: false, startsRound: false)
        }

        /// The workout with its first `count` sets logged, in order, at their rows' plans, the
        /// rest after the last skipped or not.
        func live(logged count: Int, paused: Bool = false, skipped: Bool = false) -> LiveWorkout {
            let start = Date(timeIntervalSinceReferenceDate: 1000)
            var live = LiveWorkout(
                workout: workout,
                loggedWorkout: LoggedWorkout(
                    workoutID: workout.id,
                    workoutName: "Upper",
                    startedAt: start,
                ),
            )
            for _ in 0 ..< count {
                guard let set = live.currentSet, let row = live.currentExercise else { break }
                live.loggedWorkout = live.loggedWorkout.logging(set, of: row, at: start)
            }
            if skipped, !live.loggedWorkout.sets.isEmpty {
                live.loggedWorkout.sets[live.loggedWorkout.sets.count - 1].restSkippedAt = 20
            }
            if paused {
                live.loggedWorkout = live.loggedWorkout.pausing(at: start + 60)
            }
            return live
        }

        /// The key with `logged` sets stored, nil out of a workout, drawn with `shown` of them
        /// (all, unless given), paused or not, the rest after the last skipped or not.
        func key(
            logged: Int?,
            shown: Int? = nil,
            phase: WorkoutPhase = .running,
            wayBack: WorkoutKey.WayBack? = nil,
            isScrolledAway: Bool = false,
            paused: Bool = false,
            skipped: Bool = false,
        ) -> WorkoutKey {
            WorkoutKey(
                stored: logged.map { live(logged: $0, paused: paused, skipped: skipped) },
                shown: (shown ?? logged).map { live(logged: $0, paused: paused, skipped: skipped) },
                phase: phase,
                wayBack: wayBack,
                isScrolledAway: isScrolledAway,
            )
        }
    }

    /// The phase after `set` was logged, leading to `step`, with motion.
    private static func logged(
        _ set: PlannedSet,
        leadingTo step: LiveWorkout.Step,
    ) -> WorkoutPhase {
        var phase = WorkoutPhase.running
        phase.log(set, leadingTo: step, moves: true)
        return phase
    }

    /// Out of a workout, and a set, a side, or the last set to log.
    private static func logs(_ on: Seed) -> [Row] {
        [
            Row("Out of a workout", on.key(logged: nil, phase: .idle), says: .start, taps: .start),
            Row(
                "A set to log",
                on.key(logged: 0),
                says: .log("Log set"),
                taps: .log(on.first, of: on.push, impact: .set, leadingTo: .nextSet),
            ),
            Row(
                "An exercise's last set, leading to the next exercise",
                on.key(logged: 1),
                says: .log("Log set"),
                taps: .log(on.second, of: on.push, impact: .set, leadingTo: on.toRow),
            ),
            Row(
                "Per side, left",
                on.key(logged: 2),
                says: .log("Log left"),
                taps: .log(on.left, of: on.dumbbell, impact: .side, leadingTo: .nextSet),
            ),
            Row(
                "Per side, right, the last set",
                on.key(logged: 3),
                says: .log("Log last set"),
                taps: .log(on.right, of: on.dumbbell, impact: .side, leadingTo: .last),
            ),
            Row("All sets done", on.key(logged: 4), says: .finish, taps: .finish),
        ]
    }

    /// While a log plays, where the words and the tap part: the set drawn, no tap.
    private static func playing(_ on: Seed) -> [Row] {
        [
            Row(
                "Held after a log: the set drawn, a second tap dropped",
                on.key(logged: 1, shown: 0, phase: .held(on.first)),
                says: .log("Log set"),
                taps: .nothing,
            ),
            Row(
                "Moving on: the set left's words, no tap",
                on.key(logged: 2, shown: 1, phase: logged(on.second, leadingTo: on.toRow)),
                says: .log("Log set"),
                taps: .nothing,
            ),
            Row(
                "Log last set as the row closes: no tap",
                on.key(logged: 4, shown: 3, phase: logged(on.right, leadingTo: .last)),
                says: .log("Log last set"),
                taps: .nothing,
            ),
        ]
    }

    /// With the current exercise scrolled away: the key goes back to it.
    private static func away(_ on: Seed) -> [Row] {
        let name = on.push.exercise.name
        return [
            Row(
                "Scrolled away above",
                on.key(logged: 1, wayBack: .up, isScrolledAway: true),
                says: .back(name: name, isAbove: true),
                taps: .back,
            ),
            Row(
                "Scrolled away below",
                on.key(logged: 1, wayBack: .down, isScrolledAway: true),
                says: .back(name: name, isAbove: false),
                taps: .back,
            ),
            Row(
                "Scrolled away under a finger, the key still saying Log set: back",
                on.key(logged: 1, isScrolledAway: true),
                says: .log("Log set"),
                taps: .back,
            ),
            Row(
                "Back in view under a finger, the key still pointing up: back",
                on.key(logged: 1, wayBack: .up),
                says: .back(name: name, isAbove: true),
                taps: .back,
            ),
        ]
    }

    /// As a workout ends: the stored workout gone, the key keeps the words drawn.
    private static func ending(_ on: Seed) -> [Row] {
        var phase = WorkoutPhase.running
        phase.end(on.live(logged: 1).loggedWorkout)
        return [
            Row(
                "Ending: the words drawn, a tap Start's",
                on.key(logged: nil, shown: 1, phase: phase),
                says: .log("Log set"),
                taps: .start,
            ),
        ]
    }

    static func rows() throws -> [Row] {
        let seed = try Seed()
        return try logs(seed) + playing(seed) + away(seed) + ending(seed) + restRows(seed)
            + pausedRows(seed)
    }

    @Test("The key's words and tap", arguments: try rows())
    func key(_ row: Row) {
        #expect(row.key.role == row.role)
        #expect(row.key.tap == row.tap)
        #expect(row.key.skipRest == (row.takesRestTaps ? .skipRest : .nothing))
        #expect(row.key.extendRest(by: 15) == (row.takesRestTaps ? .extendRest(by: 15) : .nothing))
    }
}
