import Foundation

/// Something a person, or the clock, did to a workout in progress, on either device. The phone
/// and the Watch both change a workout only through `LiveWorkout.applying(_:at:)`, so each runs
/// one rule for it.
public enum WorkoutAction: Equatable, Sendable {
    /// Logs the set at its row's numbers, or a timed set at the time its count ran.
    case log(PlannedSet)
    case skipRest
    case extendRest(by: Int)
    case extendCount(by: Int)
    /// The set's "Start in", or its count, began at this clock.
    case beginCount(SetCount)
    case pause
    case resume
    case finish
    case discard
}

extension LiveWorkout {
    /// The workout session with `action` applied at `date`; nil once discarded. Unchanged where
    /// the action no longer applies: a set already logged, a rest over, a pause while paused. So
    /// one heard twice changes nothing more, except `extendRest` and `extendCount`, which add,
    /// and are applied once by their number (`LinkAction.seq`). Pause and resume are two
    /// actions, never a toggle, which heard twice would undo itself.
    public func applying(_ action: WorkoutAction, at date: Date) -> WorkoutSession? {
        switch action {
        case let .log(set):
            guard let row = workout.exercises.first(where: { $0.id == set.row }) else {
                return workoutSession
            }
            return logging(set, of: row, at: date)
        case .skipRest: return skippingRest(at: date)
        case let .extendRest(seconds): return extendingRest(by: seconds, at: date)
        case let .extendCount(seconds): return extendingCount(by: seconds, at: date)
        case let .beginCount(count): return adopting(count)
        case .pause: return workoutSession.pausing(at: date)
        case .resume: return workoutSession.resuming(at: date)
        case .finish: return finishing(at: date)
        case .discard: return nil
        }
    }

    /// The workout with `count` as its current set's, when the set is still the current one
    /// and it holds none, or one begun later. The earliest start wins, keeping the +15 s taps
    /// on the one held, so two devices that each begin the same set's count end on the same
    /// one, whichever order they hear of it.
    func adopting(_ count: SetCount) -> WorkoutSession {
        guard workoutSession.isInProgress, currentSet == count.set else { return workoutSession }
        if let held = workoutSession.count, held.set == count.set,
           held.startClock <= count.startClock
        {
            return workoutSession
        }
        var adopted = workoutSession
        adopted.count = SetCount(
            set: count.set,
            startClock: count.startClock,
            added: max(count.added, workoutSession.count?.added ?? 0),
        )
        return adopted
    }

    /// When the situation next changes with nobody touching it: a rest's `leaveClock`, a "Start
    /// in"'s end, a timed set's end; `now` while a count is due and none is begun, which the
    /// device showing it begins. Nil while paused, on a set of reps, all logged, or not in
    /// progress. With `caughtUp(at:)`, which logs a count run out and begins the next set's,
    /// this is all a clock does to a workout.
    public func nextChange(after now: Date) -> Date? {
        guard workoutSession.isInProgress, !workoutSession.isPaused else { return nil }
        switch situation(at: now) {
        case let .resting(rest): return workoutSession.date(ofClock: rest.leaveClock)
        case let .countingIn(count): return workoutSession.date(ofClock: count.startClock)
        case let .doing(_, timed?): return workoutSession.date(ofClock: timed.endClock)
        case .comingUp: return now
        case .notStarted, .doing(_, nil), .allLogged, .nothingToDo: return nil
        }
    }
}
