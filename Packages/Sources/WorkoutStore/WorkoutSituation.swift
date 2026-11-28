import Foundation

/// The situation a workout is in, as the person doing it would say it. Worked out from the
/// stored logged workout and the moment (`LiveWorkout.situation(at:)`), never
/// stored. Paused is not a case: every case is read on the workout's clock, which stands still
/// while paused, so a pause keeps the situation under it.
///
/// - `notStarted`: no workout in progress. Start leads to `comingUp`.
/// - `comingUp(set)`: the workout is on `set`, a count is due before it ("Start in", or one a
///   timed set opens on), and none is begun: the screen begins it as it comes to rest on the
///   set, so all of it is seen, or as it notices the rest before it move on. After Start, a log
///   with no rest before another exercise, a set's other side, or a timed set, and a rest's
///   end not yet noticed. It leads to `countingIn`, or to `doing` on a timed set out of a rest
///   just over.
/// - `countingIn(count)`: "Start in" runs to `count.startClock`; the key takes no log. Its end
///   leads to `doing`.
/// - `doing(set, timed)`: the set is up. Reps (`timed` nil): a log ends it. Timed: its count
///   runs, a log ends it early, +15 s lengthens it, and its end logs it; a count run out while
///   nobody watched still reads as `doing` until a screen logs it (`caughtUp`). A log leads to
///   `resting`, `comingUp`, `doing` (the same exercise's next set, none due), or `allLogged`.
/// - `resting(rest)`: from a log with a rest after it until the screen moves on
///   (`WorkoutRest.leaveClock`). +15 s lengthens it; Skip rest ends it `LiveWorkout.skipHold`
///   after the tap. Its end leads to the next set's situation. Never after the last set.
/// - `allLogged`: every planned set is logged; what is left is Finish. An exercise added leads
///   back to the set it adds.
/// - `nothingToDo`: in progress on a workout whose rows were all removed.
///
/// Finish and Discard lead from any case but the first to `notStarted`.
public enum WorkoutSituation: Equatable, Sendable {
    case notStarted
    case comingUp(PlannedSet)
    case countingIn(SetCount)
    case doing(PlannedSet, TimedSet?)
    case resting(WorkoutRest)
    case allLogged
    case nothingToDo
}

extension LiveWorkout {
    /// The workout's situation at `now`, read on its clock. A rest running wins over a count
    /// Skip rest begun for the next set, which starts only as the rest moves on.
    public func situation(at now: Date) -> WorkoutSituation {
        guard loggedWorkout.isInProgress else { return .notStarted }
        guard let set = currentSet else { return isDone ? .allLogged : .nothingToDo }
        let clock = loggedWorkout.clock(at: now)
        if let rest = rest(), !rest.isOver(atClock: clock) {
            return .resting(rest)
        }
        if let count = setCount {
            return count.startClock > clock ? .countingIn(count) : .doing(set, timedSet)
        }
        return isCountDue ? .comingUp(set) : .doing(set, nil)
    }
}
