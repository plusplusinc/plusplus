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
    /// superset, for an exercise done per side, for one set, or for a rest of 0.
    public func restBetweenSets(of id: RoutineExercise.ID) -> Int? {
        guard let row = exercises.first(where: { $0.id == id }), !isInSuperset(id),
              row.plan.sets > 1, row.rest > 0,
              !setOrder.contains(where: { $0.row == id && $0.side != nil })
        else { return nil }
        return row.rest
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

    /// The rest that will follow the current exercise once its last set is logged, in seconds:
    /// nil in a superset, before nothing, before a row above it, or for a rest of 0. The rest a
    /// screen shows under the current exercise before it runs.
    public func restAfterCurrentExercise(override: Int? = nil) -> Int? {
        guard let set = currentSet, !routine.isInSuperset(set.row) else { return nil }
        let own = routine.setOrder.filter { $0.row == set.row }
        guard let last = own.last else { return nil }
        let done = Set(workout.sets.map(\.planned)).union(own)
        guard let next = routine.nextSet(notIn: done) else { return nil }
        let rows = routine.exercises.map(\.id)
        guard let from = rows.firstIndex(of: set.row), let to = rows.firstIndex(of: next.row),
              to > from
        else { return nil }
        let gap = override ?? routine.rest(after: last, before: next)
        return gap > 0 ? gap : nil
    }

    /// The rest that will follow the current set before the same exercise's next set, in
    /// seconds (`Routine.restBetweenSets(of:)`): nil when another exercise, or nothing, follows.
    public func restAfterCurrentSet(override: Int? = nil) -> Int? {
        guard let set = currentSet, let gap = routine.restBetweenSets(of: set.row) else {
            return nil
        }
        let done = Set(workout.sets.map(\.planned)).union([set])
        guard routine.nextSet(notIn: done)?.row == set.row else { return nil }
        return override ?? gap
    }
}
