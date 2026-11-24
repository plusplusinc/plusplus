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
/// the workout. Its count runs from the log to 0:00 at `endClock`, holds 0:00 for
/// `LiveWorkout.restHold`, and the screen moves on at `leaveClock` (decided 2026-11-23).
public struct WorkoutRest: Equatable, Sendable {
    /// The set it follows.
    public let after: PlannedSet
    /// The set it leads to.
    public let next: PlannedSet
    /// The workout's rest, with this rest's taps, in seconds.
    public let length: Int
    /// The clock at the log.
    public let startClock: Double
    /// Where the next set's count, begun at a skip, says the screen moves on, when sooner than
    /// the stored length does (`LiveWorkout.skippingRest(override:at:)`): a second after the tap,
    /// to the fraction, which the whole seconds stored can't hold.
    public var skipLeaveClock: Double?

    /// The clock as the count reaches 0:00.
    public var endClock: Double {
        startClock + Double(length)
    }

    /// The clock as the screen moves on, once 0:00 has held; a skip's, a second after its tap.
    public var leaveClock: Double {
        let stored = endClock + LiveWorkout.restHold
        return min(stored, skipLeaveClock ?? stored)
    }

    /// Seconds the count has left at `clock`, never below 0.
    public func remaining(atClock clock: Double) -> Double {
        max(0, endClock - clock)
    }

    /// Whether the screen moves on at `clock` (`leaveClock`).
    public func isOver(atClock clock: Double) -> Bool {
        clock >= leaveClock
    }
}

extension LiveWorkout {
    /// How long a count holds 0:00 before what follows: a rest before the screen moves on, a
    /// "Start in" before its set begins; and a skipped rest its time before the screen moves on,
    /// in seconds (decided 2026-11-23: "show 0 for a full second").
    public static let restHold = 1.0
    /// How long a skipped rest holds its time before the screen moves on, in seconds: half
    /// `restHold`, since after a tap a full second read as a hang (the maintainer, 2026-11-24).
    public static let skipHold = 0.5

    /// The rest after the last set logged, while there is one: nil with no gap after it, a set
    /// logged before its clock was kept, or nothing left to do. Whether it is over is the
    /// caller's, at its moment. `override`, for the UI tests, replaces every rest's length where
    /// the workout has one, never where it has none, as between a set's sides.
    public func rest(override: Int? = nil) -> WorkoutRest? {
        guard let last = loggedWorkout.sets.last, let start = last.clockWhenLogged,
              let next = currentSet
        else { return nil }
        let stored = workout.rest(after: last.planned, before: next)
        let gap = stored > 0 ? override ?? stored : 0
        guard gap > 0 else { return nil }
        var rest = WorkoutRest(
            after: last.planned,
            next: next,
            length: max(0, gap + last.restAdjustment),
            startClock: start,
        )
        // A count for the next set begun before the rest moves on is a skip's: it moves on as
        // that count's "Start in" begins. One begun at or after the move puts it no sooner.
        if let count = setCount {
            rest.skipLeaveClock = count.startClock - countLead(before: next)
        }
        return rest
    }

    /// How long before `set` begins its count's "Start in" does, with its hold; 0 for none.
    private func countLead(before set: PlannedSet) -> Double {
        let startIn = workout.startIn(before: set)
        return startIn > 0 ? Double(startIn) + Self.startInHold : 0
    }

    /// The workout with the rest running after the last set made longer by `seconds`, as a +15 s
    /// tap does, at `now`. Unchanged with no rest running, once it reads 0:00, or once skipped,
    /// so a tap landing as it ends brings nothing back.
    public func extendingRest(
        by seconds: Int,
        override: Int? = nil,
        at now: Date,
    ) -> LoggedWorkout {
        guard loggedWorkout.isInProgress, setCount == nil, let rest = rest(override: override),
              rest.remaining(atClock: loggedWorkout.clock(at: now)) > 0
        else { return loggedWorkout }
        var extended = loggedWorkout
        extended.sets[extended.sets.count - 1].restAdjustment += seconds
        return extended
    }

    /// The workout with the rest running after the last set cut short at `now`, as a tap on Skip
    /// rest does. Its count holds the time at the tap for `skipHold` before the screen moves
    /// on, as one run out holds 0:00, for less time. Where the next set has a
    /// count due, a "Start in" or a timed set's own, it is begun here, to the fraction of a
    /// second, so the rest moves on exactly a second after the tap
    /// (`WorkoutRest.skipLeaveClock`) and a relaunch finds the count where the screen had it.
    /// The stored adjustment holds the rest taken in whole seconds: rounded up where a count
    /// times the move, so the count's move is never later than the stored one; rounded down
    /// where none does, a reps set between sets, so the screen's own second after the tap is
    /// never sooner (`WorkoutScreen.skipLeave`). Unchanged with no rest running, once it reads
    /// 0:00, or skipped already.
    public func skippingRest(override: Int? = nil, at now: Date) -> LoggedWorkout {
        let clock = loggedWorkout.clock(at: now)
        guard loggedWorkout.isInProgress, setCount == nil, let rest = rest(override: override),
              rest.remaining(atClock: clock) > 0
        else { return loggedWorkout }
        var skipped = loggedWorkout
        let lead = countLead(before: rest.next)
        let counts = lead > 0 || isOnTimedSet
        let taken = clock - rest.startClock
        let rested = Int(counts ? taken.rounded(.up) : taken.rounded(.down))
        skipped.sets[skipped.sets.count - 1].restAdjustment += rested - rest.length
        if counts {
            skipped.count = SetCount(set: rest.next, startClock: clock + Self.skipHold + lead)
        }
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
    /// promise before the log: `rests(after:leadingTo:override:)`'s rule.
    public func restLength(
        after set: PlannedSet,
        leadingTo step: Step,
        override: Int? = nil,
    ) -> Int {
        let stored: Int
        switch step {
        case let .nextExercise(next, isBack, _) where !isBack || workout.isInSuperset(set.row):
            stored = workout.rest(after: set, before: next)
        case .nextSet:
            stored = workout.restBetweenSets(after: set) ?? 0
        default:
            return 0
        }
        return stored > 0 ? override ?? stored : 0
    }
}
