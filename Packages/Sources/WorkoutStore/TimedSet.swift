import Foundation

/// The timed set whose turn has come in a workout, until it is logged: the stored half of
/// `TimedSet`. Its set is kept with it, since a count holds only for the set it was begun for:
/// a row deleted, moved, or changed to reps mid-count makes another set current.
public struct SetCount: Equatable, Sendable {
    public let set: PlannedSet
    /// The workout's clock (`LoggedWorkout.clock(at:)`) as the set's own count starts: ahead of the
    /// clock during "Starts in".
    public var startClock: Double
    /// The +15 s taps on this set, in seconds.
    public var added: Int

    public init(set: PlannedSet, startClock: Double, added: Int = 0) {
        self.set = set
        self.startClock = startClock
        self.added = added
    }
}

/// A timed set's count as its log stopped it: its length, +15 s taps in, and the seconds done.
public struct LoggedCount: Equatable, Sendable {
    public let length: Int
    public let done: Int

    /// The seconds the count had left.
    public var left: Double {
        Double(max(0, length - done))
    }
}

/// Where a timed set's count stands: its short "Starts in" count, then its own.
public enum CountStage: Sendable {
    case startsIn
    case counting
}

/// A timed set counting on the workout's clock, so a pause stops it, as `WorkoutRest` does: a
/// short "Starts in" count until `startClock`, then the set's own for `length`.
public struct TimedSet: Equatable, Sendable {
    public let set: PlannedSet
    public let startClock: Double
    /// The row's time now, with this set's +15 s taps, in seconds.
    public let length: Int
    /// The +15 s taps, in seconds.
    public let added: Int

    /// The clock as the set's own count ends.
    public var endClock: Double {
        startClock + Double(length)
    }

    /// Seconds of "Starts in" left at `clock`; 0 once the set counts.
    public func startsIn(atClock clock: Double) -> Double {
        max(0, startClock - clock)
    }

    /// Seconds of the set's own count left at `clock`: all of it during "Starts in", never
    /// below 0.
    public func remaining(atClock clock: Double) -> Double {
        min(Double(length), max(0, endClock - clock))
    }

    public func isOver(atClock clock: Double) -> Bool {
        clock >= endClock
    }

    /// The seconds done at `clock`, as the count shows them: 0:18 shows while 17 to 18 s are
    /// left, so a log then is 12 of 30.
    public func done(atClock clock: Double) -> Int {
        max(0, length - Int(remaining(atClock: clock).rounded(.up)))
    }
}

extension LiveWorkout {
    /// The seconds of "Starts in" before a timed set no rest leads into.
    public static let startsIn = 10
    /// How long after a rest ends a timed set's count still starts at the rest's end, in
    /// seconds: a screen noticing the end a moment late. Later, as after time away, it opens on
    /// "Starts in" from now, so nothing is logged that nobody saw start.
    static let missedBy = 1.0

    /// The count begun for the current set: nil for a reps set, with none begun, or one begun
    /// for another set.
    public var timedSet: TimedSet? {
        guard let count = workout.count, count.set == currentSet,
              let row = currentExercise, case let .time(seconds) = row.plan.target
        else { return nil }
        return TimedSet(
            set: count.set,
            startClock: count.startClock,
            length: seconds + count.added,
            added: count.added,
        )
    }

    /// Where the current set's count stands at `now`: nil with none.
    public func countStage(at now: Date) -> CountStage? {
        guard let timed = timedSet else { return nil }
        return timed.startsIn(atClock: workout.clock(at: now)) > 0 ? .startsIn : .counting
    }

    /// The count `set` stopped at as it was logged: nil for a set not logged, or not timed.
    public func loggedCount(of set: PlannedSet) -> LoggedCount? {
        guard let logged = workout.sets.last(where: { $0.planned == set }),
              case let .time(done) = logged.target,
              case let .time(planned) = logged.plannedTarget
        else { return nil }
        return LoggedCount(length: planned + logged.timeAdded, done: done)
    }

    /// Whether the current set is timed, so its turn begins a count.
    public var isOnTimedSet: Bool {
        guard let row = currentExercise, case .time = row.plan.target else { return false }
        return true
    }

    /// The workout with the current set's count begun at `now`, when it is timed and has none of
    /// its own: at the end of the rest before it, when that just ended; else after "Starts in"
    /// from now. A count kept for no set counting goes, as after the set changed to reps, so it
    /// never comes back with its old start; the rest of the workout is unchanged while the rest
    /// before the set runs.
    public func beginningCount(at now: Date, restOverride: Int? = nil) -> LoggedWorkout {
        guard workout.isInProgress, timedSet == nil else { return workout }
        var begun = workout
        begun.count = nil
        guard let set = currentSet, isOnTimedSet else { return begun }
        let clock = workout.clock(at: now)
        var start = clock + Double(Self.startsIn)
        if let rest = rest(override: restOverride) {
            guard rest.isOver(atClock: clock) else { return begun }
            if clock - rest.endClock <= Self.missedBy {
                start = rest.endClock
            }
        }
        begun.count = SetCount(set: set, startClock: start)
        return begun
    }

    /// The workout with `set`, a set of `row`, logged at `now`. A set with a count logs the time
    /// done, its +15 s taps, and, when it ran out, the clock and the time of day at its end, so
    /// the rest after it starts where the set ended, and the set reads as done then, however
    /// late it is noticed. The end's time of day is the clock's at the end, read as if no pause
    /// was resumed since: a count can't end in a pause, and the gap to its log is time away from
    /// the count, the phone locked or the app gone, so a pause resumed inside it isn't expected;
    /// one would put the time of day late by its length. The next
    /// set's count is not begun here: with no rest before it, its "Starts in" begins as the
    /// screen lands on it, so its ten seconds are all seen (`beginningCount(at:restOverride:)`).
    public func logging(_ set: PlannedSet, of row: RoutineExercise, at now: Date) -> LoggedWorkout {
        let clock = workout.clock(at: now)
        let timed = timedSet.flatMap { $0.set == set ? $0 : nil }
        let endClock = timed.flatMap { $0.isOver(atClock: clock) ? $0.endClock : nil }
        var logged = workout.logging(
            set,
            of: row,
            at: endClock.map(workout.date(ofClock:)) ?? now,
        )
        guard logged.sets.count > workout.sets.count else { return workout }
        if let timed {
            let last = logged.sets.count - 1
            logged.sets[last].target = .time(seconds: timed.done(atClock: clock))
            logged.sets[last].timeAdded = timed.added
            if let endClock {
                logged.sets[last].clockWhenLogged = endClock
            }
        }
        logged.count = nil
        return logged
    }

    /// The workout finished at `now` (`LoggedWorkout.finishing(at:)`), a set counting logged first
    /// at
    /// the time done, as a log at that moment logs it, and one whose count ran out at its full
    /// time. A set still in "Starts in" logs nothing: it never began. Paused, the set is logged
    /// as the pause began, where its count stopped, so its time of day and its clock agree.
    public func finishing(at now: Date) -> LoggedWorkout {
        guard countStage(at: now) == .counting, let timed = timedSet, let row = currentExercise
        else { return workout.finishing(at: now) }
        return logging(timed.set, of: row, at: workout.pausedAt ?? now).finishing(at: now)
    }

    /// The workout with "Starts in" cut short at `now`: the set counts from now. Unchanged
    /// outside "Starts in".
    public func startingCountNow(at now: Date) -> LoggedWorkout {
        let clock = workout.clock(at: now)
        guard workout.isInProgress, let timed = timedSet, timed.startsIn(atClock: clock) > 0
        else { return workout }
        var started = workout
        started.count?.startClock = clock
        return started
    }

    /// The workout with `seconds` added to the set counting, as a +15 s tap does. Unchanged
    /// during "Starts in" or once over, so a tap landing as it ends brings nothing back.
    public func extendingCount(by seconds: Int, at now: Date) -> LoggedWorkout {
        let clock = workout.clock(at: now)
        guard workout.isInProgress, let timed = timedSet, timed.startsIn(atClock: clock) == 0,
              !timed.isOver(atClock: clock)
        else { return workout }
        var extended = workout
        extended.count?.added += seconds
        return extended
    }

    /// The workout as a screen opening at `now` finds it: a count that ran out meanwhile
    /// logged at its full time, then the next set's count begun. One set, never a chain.
    public func caughtUp(at now: Date, restOverride: Int? = nil) -> LoggedWorkout {
        var live = self
        if let timed = timedSet, timed.isOver(atClock: workout.clock(at: now)),
           let row = currentExercise
        {
            live = LiveWorkout(routine: routine, workout: logging(timed.set, of: row, at: now))
        }
        return live.beginningCount(at: now, restOverride: restOverride)
    }
}
