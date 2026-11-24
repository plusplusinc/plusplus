import Foundation

extension Workout {
    /// The rest between `set` and `next`, in seconds, as the workout stores it now: none after the
    /// workout's last set, or the set's row gone; none between a set's two sides, or between a
    /// superset's members in one round; a superset's rest after each round where a round ends;
    /// else the row's own rest, to its next set or to another exercise alike.
    public func rest(after set: PlannedSet, before next: PlannedSet?) -> Int {
        guard let next, let row = exercises.first(where: { $0.id == set.row }) else { return 0 }
        if let round = restAfterRound(of: set.row) {
            let sameSuperset = exercises.first { $0.id == next.row }?.supersetID == row.supersetID
            return sameSuperset && next.round == set.round ? 0 : round
        }
        return next.row == set.row && next.round == set.round ? 0 : row.rest
    }

    /// The rest between two sets of `id`, in seconds, where a screen runs one: none in a
    /// superset, for one set, or for a rest of 0. An exercise done per side rests after each
    /// set's last side, as a plain one after each set.
    public func restBetweenSets(of id: WorkoutExercise.ID) -> Int? {
        guard let row = exercises.first(where: { $0.id == id }), !isInSuperset(id),
              row.plan.sets > 1, row.rest > 0
        else { return nil }
        return row.rest
    }

    /// The rest between sets that follows `set`, where its row rests between them: none after a
    /// side its other side follows.
    public func restBetweenSets(after set: PlannedSet) -> Int? {
        guard let row = exercises.first(where: { $0.id == set.row }),
              set.side == row.sides.last
        else { return nil }
        return restBetweenSets(of: set.row)
    }
}

/// The rest running after a set, on the workout's clock (`LoggedWorkout.clock(at:)`), so a pause
/// stops it. It holds no date: it changes only with a log, a +15 s tap, a skip, or an edit to
/// the workout. Its count runs from the log to 0:00 at `endClock`. Where a "Start in" is due
/// before the next set (`Workout.startIn(before:)`, as another exercise comes up), its last
/// `startIn` seconds are that "Start in": the screen moves on to the next exercise with them
/// left (`leaveClock`), and its "Start in" counts them down in the exercise's figures' slot to
/// 0:00 at `endClock`, which it holds for `LiveWorkout.restHold` before the set begins
/// (decided 2026-11-23). Between two sets of one exercise, none: the count holds 0:00 that long,
/// then the screen swaps back.
public struct WorkoutRest: Equatable, Sendable {
    /// The set it follows.
    public let after: PlannedSet
    /// The set it leads to.
    public let next: PlannedSet
    /// The workout's rest, with this rest's taps, in seconds: from the log to 0:00, its "Start
    /// in" included.
    public let length: Int
    /// The clock at the log.
    public let startClock: Double
    /// The seconds of "Start in" its end holds: 0 between two sets of one exercise.
    public var startIn = 0

    /// The clock as the count reaches 0:00.
    public var endClock: Double {
        startClock + Double(length)
    }

    /// The clock as the screen moves on: on to the next exercise with `startIn` seconds left,
    /// or, between sets, back to the set once 0:00 has held.
    public var leaveClock: Double {
        startIn > 0
            ? max(startClock, endClock - Double(startIn))
            : endClock + LiveWorkout.restHold
    }

    /// The clock as its keys go: as it leaves, or between sets at 0:00.
    public var keysGoClock: Double {
        min(leaveClock, endClock)
    }

    /// Seconds the count has left at `clock`, never below 0.
    public func remaining(atClock clock: Double) -> Double {
        max(0, endClock - clock)
    }

    /// Whether its keys have gone at `clock` (`keysGoClock`): +15 s and Skip rest change
    /// nothing from then.
    public func hasGivenWay(atClock clock: Double) -> Bool {
        clock >= keysGoClock
    }

    /// Whether the screen moves on at `clock` (`leaveClock`).
    public func isOver(atClock clock: Double) -> Bool {
        clock >= leaveClock
    }
}

extension LiveWorkout {
    /// How long a count holds 0:00 before what follows: a rest before the swap back, a "Start
    /// in" before its set begins; and a skipped rest its time before the screen moves on, in
    /// seconds (decided 2026-11-23: "show 0 for a full second").
    public static let restHold = 1.0

    /// The rest after the last set logged, while there is one: nil with no gap after it, a set
    /// logged before its clock was kept, or nothing left to do. Whether it is over is the
    /// caller's, at its moment. `override`, for the UI tests, replaces every rest's length where
    /// the workout has one, never where it has none, as between a set's sides. A rest no longer
    /// than the "Start in" due before the next set is none: the move goes straight on, and that
    /// "Start in" is all of it.
    public func rest(override: Int? = nil) -> WorkoutRest? {
        guard let last = loggedWorkout.sets.last, let start = last.clockWhenLogged,
              let next = currentSet
        else { return nil }
        let stored = workout.rest(after: last.planned, before: next)
        let gap = stored > 0 ? override ?? stored : 0
        let length = max(0, gap + last.restAdjustment)
        let startIn = workout.startIn(before: next)
        guard gap > 0, length > startIn else { return nil }
        return WorkoutRest(
            after: last.planned,
            next: next,
            length: length,
            startClock: start,
            startIn: startIn,
        )
    }

    /// The workout with the rest running after the last set made longer by `seconds`, as a +15 s
    /// tap does, at `now`. Unchanged with no rest running, or once it has given way, so a tap
    /// landing as its keys go brings nothing back.
    public func extendingRest(
        by seconds: Int,
        override: Int? = nil,
        at now: Date,
    ) -> LoggedWorkout {
        guard loggedWorkout.isInProgress, let rest = rest(override: override),
              !rest.hasGivenWay(atClock: loggedWorkout.clock(at: now))
        else { return loggedWorkout }
        var extended = loggedWorkout
        extended.sets[extended.sets.count - 1].restAdjustment += seconds
        return extended
    }

    /// The workout with the rest running after the last set cut short at `now`, as a tap on Skip
    /// rest does, its stored adjustment holding the rest taken. Its count holds the time at the
    /// tap for a second (`restHold`), to whole seconds from its log, so at least that, before the
    /// screen moves on: between two sets of one exercise, back to the set; before another
    /// exercise, on to it, with its "Start in" whole (decided 2026-11-23). Unchanged with no rest
    /// running, or once its keys have gone.
    public func skippingRest(override: Int? = nil, at now: Date) -> LoggedWorkout {
        let clock = loggedWorkout.clock(at: now)
        guard loggedWorkout.isInProgress, let rest = rest(override: override),
              !rest.hasGivenWay(atClock: clock)
        else { return loggedWorkout }
        var skipped = loggedWorkout
        let rested = Int((clock - rest.startClock).rounded(.up))
        let held = rest.startIn > 0 ? Int(Self.restHold) + rest.startIn : 0
        skipped.sets[skipped.sets.count - 1].restAdjustment += rested + held - rest.length
        return skipped
    }

    /// Whether logging `set`, already stored, leading to `step`, rests first: on to another
    /// exercise down the rail, or back up a superset's loop to its next round, with a rest after
    /// it; or on to the same row's next set, with a rest between its sets, after a set's last side
    /// when it is done one side at a time, never between its sides.
    public func rests(after set: PlannedSet, leadingTo step: Step, override: Int? = nil) -> Bool {
        restLength(after: set, leadingTo: step, override: override) > 0
            && rest(override: override) != nil
    }

    /// The seconds of rest logging `set` leading to `step` runs, 0 for none, which a screen can
    /// promise before the log: `rests(after:leadingTo:override:)`'s rule. None where it is no
    /// longer than the next set's "Start in" (`rest(override:)`).
    public func restLength(
        after set: PlannedSet,
        leadingTo step: Step,
        override: Int? = nil,
    ) -> Int {
        let stored: Int
        var startIn = 0
        switch step {
        case let .nextExercise(next, isBack, _) where !isBack || workout.isInSuperset(set.row):
            stored = workout.rest(after: set, before: next)
            startIn = workout.startIn(before: next)
        case .nextSet:
            stored = workout.restBetweenSets(after: set) ?? 0
        default:
            return 0
        }
        let length = stored > 0 ? override ?? stored : 0
        return length > startIn ? length : 0
    }
}
