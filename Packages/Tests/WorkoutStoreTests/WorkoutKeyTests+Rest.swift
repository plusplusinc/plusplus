import Foundation
import Testing
@testable import WorkoutStore

/// The key during a rest: Skip rest and +15 s in its place, between sets, between exercises, and
/// after a superset's round, and which beats of the rest they change it in.
extension WorkoutKeyTests {
    /// The phase after `set` was logged with a rest after it, leading to `step`, played on to
    /// `beat` as the screen plays it: drawn, landed between exercises, settled, and, between
    /// sets, returning.
    private static func resting(
        _ set: PlannedSet,
        leadingTo step: LiveWorkout.Step,
        to beat: WorkoutPhase.Resting.Beat,
    ) -> WorkoutPhase {
        var phase = WorkoutPhase.running
        phase.log(set, leadingTo: step, rests: true, moves: true)
        if beat >= .shown {
            phase.show()
        }
        if beat >= .landed {
            phase.landRest()
        }
        if beat >= .settled {
            phase.settleRest()
        }
        if beat >= .returning {
            phase.endRest()
        }
        return phase
    }

    static func restRows(_ on: Seed) throws -> [Row] {
        try betweenSets(on) + betweenExercises(on) + endingInRest(on) + supersetRound()
    }

    /// During a rest between sets: Skip rest and +15 s in the key's place from the log, changing
    /// the rest once the swap is over, until the next set swaps back.
    private static func betweenSets(_ on: Seed) -> [Row] {
        let rest = { (beat: WorkoutPhase.Resting.Beat) in
            resting(on.first, leadingTo: .nextSet, to: beat)
        }
        return [
            Row(
                "Rest between sets, just logged: the rest's keys, not yet taking a tap",
                on.key(logged: 1, shown: 0, phase: rest(.logged)),
                says: .rest,
                taps: .nothing,
            ),
            Row(
                "Rest between sets, swapping in: the rest's keys, not yet taking a tap",
                on.key(logged: 1, phase: rest(.shown)),
                says: .rest,
                taps: .nothing,
            ),
            Row(
                "Rest between sets, under way: the rest's keys change it",
                on.key(logged: 1, phase: rest(.settled)),
                says: .rest,
                taps: .nothing,
                takesRestTaps: true,
            ),
            Row(
                "Rest between sets over, the next set swapping back: Log set, no tap yet",
                on.key(logged: 1, phase: rest(.returning)),
                says: .log("Log set"),
                taps: .nothing,
            ),
            Row(
                "Rest between sets, scrolled away: back, the rest still changing",
                on.key(logged: 1, phase: rest(.settled), wayBack: .up, isScrolledAway: true),
                says: .back(name: on.push.exercise.name, isAbove: true),
                taps: .back,
                takesRestTaps: true,
            ),
        ]
    }

    /// During a rest between exercises: the rest's keys from the log, changing the rest once the
    /// pulse has landed at it.
    private static func betweenExercises(_ on: Seed) -> [Row] {
        let rest = { (beat: WorkoutPhase.Resting.Beat) in
            resting(on.second, leadingTo: on.toRow, to: beat)
        }
        return [
            Row(
                "Rest between exercises, the move into it: the rest's keys, no tap",
                on.key(logged: 2, phase: rest(.shown)),
                says: .rest,
                taps: .nothing,
            ),
            Row(
                "Rest between exercises, landed: the rest's keys change it",
                on.key(logged: 2, phase: rest(.landed)),
                says: .rest,
                taps: .nothing,
                takesRestTaps: true,
            ),
            Row(
                "Rest between exercises, settled: the rest's keys change it",
                on.key(logged: 2, phase: rest(.settled)),
                says: .rest,
                taps: .nothing,
                takesRestTaps: true,
            ),
        ]
    }

    /// Ending in a rest: the rest's keys stay while the list draws the workout, taking no tap.
    private static func endingInRest(_ on: Seed) -> [Row] {
        var phase = resting(on.second, leadingTo: on.toRow, to: .settled)
        phase.end(on.live(logged: 2).loggedWorkout)
        return [
            Row(
                "Ending in a rest: the rest's keys drawn, a tap Start's",
                on.key(logged: nil, shown: 2, phase: phase),
                says: .rest,
                taps: .start,
            ),
        ]
    }

    /// A superset of Dumbbell bench press and Pull-up, two rounds: the round's rest after the
    /// first round, above the first member, back up the loop.
    private static func supersetRound() throws -> [Row] {
        var routine = try Workout(exercises: [
            WorkoutExercise.builtIn("Dumbbell bench press") { $0.sets = 2 },
            WorkoutExercise.builtIn("Pull-up") { $0.sets = 2 },
        ])
        routine.join(routine.exercises[0].id, .below)
        routine.setRestAfterRound(60, of: routine.exercises[0].id)
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        let started = LoggedWorkout(routineID: routine.id, routineName: "Pull", startedAt: start)
        var live = LiveWorkout(routine: routine, loggedWorkout: started)
        let bench = try #require(live.currentSet)
        live.loggedWorkout = try live.loggedWorkout.logging(
            bench,
            of: #require(live.currentExercise),
            at: start,
        )
        let pull = try #require(live.currentSet)
        let step = live.step(logging: pull)
        guard case .nextExercise(_, isBack: true, _) = step else {
            Issue.record("The first round's last member should lead back up the loop: \(step)")
            return []
        }
        let before = live
        live.loggedWorkout = try live.loggedWorkout.logging(
            pull,
            of: #require(live.currentExercise),
            at: start,
        )
        let key = { (shown: LiveWorkout, beat: WorkoutPhase.Resting.Beat) in
            WorkoutKey(
                stored: live,
                shown: shown,
                phase: resting(pull, leadingTo: step, to: beat),
                wayBack: nil,
                isScrolledAway: false,
            )
        }
        return [
            Row(
                "Superset round's rest, just logged: the rest's keys, no tap",
                key(before, .logged),
                says: .rest,
                taps: .nothing,
            ),
            Row(
                "Superset round's rest, landed: the rest's keys change it",
                key(live, .landed),
                says: .rest,
                taps: .nothing,
                takesRestTaps: true,
            ),
            Row(
                "Superset round's rest, settled: the rest's keys change it",
                key(live, .settled),
                says: .rest,
                taps: .nothing,
                takesRestTaps: true,
            ),
        ]
    }
}
