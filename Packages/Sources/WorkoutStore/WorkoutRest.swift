import Foundation

extension Routine {
    /// The rest between `set` and `next`, in seconds, as the routine stores it now: none after the
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
    public func restBetweenSets(of id: RoutineExercise.ID) -> Int? {
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

/// The rest running after a set, on the workout's clock (`Workout.clock(at:)`), so a pause stops
/// it. It holds no date: it changes only with a log, a + or − tap, or an edit to the routine.
/// −15 s needs no rule of its own: the length drops, and a rest with less left is over.
public struct WorkoutRest: Equatable, Sendable {
    /// The set it follows.
    public let after: PlannedSet
    /// The set it leads to.
    public let next: PlannedSet
    /// The routine's rest, with this rest's taps, in seconds.
    public let length: Int
    /// The clock at the log.
    public let startClock: Double

    /// The clock as the rest ends.
    public var endClock: Double {
        startClock + Double(length)
    }

    /// Seconds left at `clock`, never below 0.
    public func remaining(atClock clock: Double) -> Double {
        max(0, endClock - clock)
    }

    public func isOver(atClock clock: Double) -> Bool {
        remaining(atClock: clock) <= 0
    }
}

extension LiveWorkout {
    /// The rest after the last set logged, while there is one: nil with no gap after it, a set
    /// logged before its clock was kept, or nothing left to do. Whether it is over is the
    /// caller's, at its moment. `override`, for the UI tests, replaces every rest's length where
    /// the routine has one, never where it has none, as between a set's sides.
    public func rest(override: Int? = nil) -> WorkoutRest? {
        guard let last = workout.sets.last, let start = last.clockWhenLogged,
              let next = currentSet
        else { return nil }
        let stored = routine.rest(after: last.planned, before: next)
        let gap = stored > 0 ? override ?? stored : 0
        guard gap > 0 else { return nil }
        return WorkoutRest(
            after: last.planned,
            next: next,
            length: max(0, gap + last.restAdjustment),
            startClock: start,
        )
    }

    /// The workout with the rest running after the last set changed by `seconds`, as a + or − tap
    /// does, at `now`. Unchanged with no rest running, or once it is over, so a tap landing as it
    /// ends brings nothing back.
    public func adjustingRest(by seconds: Int, override: Int? = nil, at now: Date) -> Workout {
        guard workout.isInProgress, let rest = rest(override: override),
              !rest.isOver(atClock: workout.clock(at: now))
        else { return workout }
        var adjusted = workout
        adjusted.sets[adjusted.sets.count - 1].restAdjustment += seconds
        // A cut past the rest's end ends it now: a timed set next counts from the tap, not from
        // where the cut put the end, up to 15 s back, which read as a rest missed.
        let clock = workout.clock(at: now)
        let next = LiveWorkout(routine: routine, workout: adjusted)
        if next.rest(override: override)?.isOver(atClock: clock) == true, next.isOnTimedSet,
           let set = next.currentSet
        {
            adjusted.count = SetCount(set: set, startClock: clock)
        }
        return adjusted
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
        case let .nextExercise(next, isBack, _) where !isBack || routine.isInSuperset(set.row):
            stored = routine.rest(after: set, before: next)
        case .nextSet:
            stored = routine.restBetweenSets(after: set) ?? 0
        default:
            return 0
        }
        return stored > 0 ? override ?? stored : 0
    }
}
