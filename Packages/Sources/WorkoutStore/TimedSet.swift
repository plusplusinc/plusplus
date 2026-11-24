import Foundation

/// The set whose turn has come in a workout, while its "Start in" runs or its count does, until
/// it is logged: the stored half of `TimedSet`. Its set is kept with it, since a count holds only
/// for the set it was begun for: a row deleted, moved, or changed to reps mid-count makes another
/// set current. A reps set's holds only its "Start in", whose end is `startClock`.
public struct SetCount: Equatable, Sendable {
    public let set: PlannedSet
    /// The workout's clock (`LoggedWorkout.clock(at:)`) as "Start in" ends and a timed set's own
    /// count starts: ahead of the clock during "Start in".
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

/// Where a set's count stands: its short "Start in" count, then, on a timed set, its own.
public enum CountStage: Sendable {
    case startIn
    case counting
}

/// A timed set counting on the workout's clock, so a pause stops it, as `WorkoutRest` does: a
/// short "Start in" count until `startClock`, then the set's own for `length`.
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

    /// Seconds of "Start in" left at `clock`; 0 once the set counts.
    public func startIn(atClock clock: Double) -> Double {
        max(0, startClock - clock)
    }

    /// Seconds of the set's own count left at `clock`: all of it during "Start in", never
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

extension Workout {
    /// The seconds of "Start in" before `set`, in the order sets are done (`setOrder`), reps and
    /// timed alike (decided 2026-11-23): `LiveWorkout.startIn` before the workout's first set and
    /// whenever the set before it was another exercise's, as each exercise comes up and between a
    /// superset's members in every round; `LiveWorkout.startInSides` before a set's other side;
    /// none before a later set of the same exercise.
    public func startIn(before set: PlannedSet) -> Int {
        let order = setOrder
        guard let index = order.firstIndex(of: set), index > 0 else { return LiveWorkout.startIn }
        return Self.startIn(before: set, after: order[index - 1])
    }

    /// The rule of `startIn(before:)`, given the set done before `set`, nil for none, so a
    /// walk over `setOrder` asks it in one pass.
    static func startIn(before set: PlannedSet, after previous: PlannedSet?) -> Int {
        guard let previous, previous.row == set.row else { return LiveWorkout.startIn }
        return previous.round == set.round && previous.side != set.side
            ? LiveWorkout.startInSides : 0
    }
}

extension LiveWorkout {
    /// The seconds of "Start in" as an exercise comes up (5 since 2026-11-23; the maintainer may
    /// yet want 10 back here, apart from the sides').
    public static let startIn = 5
    /// The seconds of "Start in" before the other side of a set done per side.
    public static let startInSides = 5
    /// How long every "Start in" holds 0:00 before its set begins, past its own length: a
    /// count's `startClock` is the set's start, this long after "Start in" reads 0:00.
    public static let startInHold = restHold
    /// How long after a rest ends a set's "Start in", or a timed set's count, still starts at the
    /// rest's end, in seconds: a screen noticing the end a moment late. Later, as after time
    /// away, it starts from now, and a timed set with none due opens on "Start in" from now, so
    /// nothing is logged that nobody saw start.
    static let missedBy = 1.0

    /// The count begun for the current set, timed or reps: nil with none begun, or one begun for
    /// another set.
    public var setCount: SetCount? {
        guard let count = loggedWorkout.count, count.set == currentSet else { return nil }
        return count
    }

    /// The count begun for the current set: nil for a reps set, with none begun, or one begun
    /// for another set.
    public var timedSet: TimedSet? {
        guard let count = setCount, let row = currentExercise,
              case let .time(seconds) = row.plan.target
        else { return nil }
        return TimedSet(
            set: count.set,
            startClock: count.startClock,
            length: seconds + count.added,
            added: count.added,
        )
    }

    /// Where the current set's count stands at `now`: "Start in" while it runs, on a reps set
    /// as on a timed one; then a timed set's own count; nil with none, and for a reps set once
    /// its "Start in" is over.
    public func countStage(at now: Date) -> CountStage? {
        guard let count = setCount else { return nil }
        if count.startClock > loggedWorkout.clock(at: now) {
            return .startIn
        }
        return isOnTimedSet ? .counting : nil
    }

    /// The seconds of "Start in" due before the current set, or, with none due, the one a timed
    /// set opens on after time away (`beginningCount(at:restOverride:fresh:)`).
    public var startInLength: Int {
        let due = currentSet.map { workout.startIn(before: $0) } ?? 0
        return due > 0 ? due : Self.startIn
    }

    /// The count `set` stopped at as it was logged: nil for a set not logged, or not timed.
    public func loggedCount(of set: PlannedSet) -> LoggedCount? {
        guard let logged = loggedWorkout.sets.last(where: { $0.planned == set }),
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

    /// The logged workout as `edited` replaces the workout: a count kept for a set whose row
    /// changed measure, reps to a time or back, goes, so it never comes back with its old start
    /// and the set opens on the "Start in" due before it from the edit
    /// (`beginningCount(at:restOverride:)`). Decided as the edit is written, never from a
    /// reaction to it, which SwiftUI can skip for a second change in one frame.
    public func droppingCount(for edited: Workout) -> LoggedWorkout {
        guard let count = loggedWorkout.count,
              let before = workout.exercises.first(where: { $0.id == count.set.row }),
              let after = edited.exercises.first(where: { $0.id == count.set.row }),
              before.plan.target.isTime != after.plan.target.isTime
        else { return loggedWorkout }
        var dropped = loggedWorkout
        dropped.count = nil
        return dropped
    }

    /// The workout as the screen lands on its first set after Start, at `now`: the set's "Start
    /// in" begins there, and the workout's time starts as it ends, where the set begins
    /// (decided 2026-11-23), so the time reads 0:00 through "Start in" and the two turn over
    /// together. The clock stands below zero until then (`LoggedWorkout.clock(at:)`).
    /// Only a workout with nothing logged, never paused, no count yet, and under a second on
    /// its clock, so its time has shown only 0:00 and none of it is lost: any other, as one
    /// whose landing waited on the phone being unlocked, only begins its count.
    public func landingStart(at now: Date, restOverride: Int? = nil) -> LoggedWorkout {
        guard loggedWorkout.isInProgress, loggedWorkout.sets.isEmpty, loggedWorkout.count == nil,
              loggedWorkout.pausedAt == nil, loggedWorkout.pausedSeconds == 0,
              loggedWorkout.clock(at: now) < 1
        else { return beginningCount(at: now, restOverride: restOverride) }
        var landed = loggedWorkout
        landed.startedAt = now
        let begun = LiveWorkout(workout: workout, loggedWorkout: landed)
            .beginningCount(at: now, restOverride: restOverride)
        return Self.timeStartingAtCount(begun)
    }

    /// `begun` with its time starting as its count's "Start in" ends: for a workout whose
    /// time hasn't started, its first set's count begun at the landing or again after an edit.
    private static func timeStartingAtCount(_ begun: LoggedWorkout) -> LoggedWorkout {
        guard let lead = begun.count?.startClock else { return begun }
        var held = begun
        held.startedAt = begun.startedAt.addingTimeInterval(lead)
        held.count?.startClock = 0
        return held
    }

    /// The workout with the current set's count begun at `now`, when it has none of its own:
    /// with the "Start in" due before it (`Workout.startIn(before:)`) from where the rest before
    /// it moved on, its 0:00 held (`WorkoutRest.leaveClock`), when that just happened, else from
    /// now. A timed set with none due counts from the rest's move on, when that just happened,
    /// else opens on `startIn` from now; a reps set with none due begins nothing. Every "Start
    /// in" holds 0:00 for `startInHold` before the set begins. A count kept for no set goes. The
    /// rest of the workout is unchanged until the rest before the set moves on.
    public func beginningCount(at now: Date, restOverride: Int? = nil) -> LoggedWorkout {
        guard loggedWorkout.isInProgress, setCount == nil else { return loggedWorkout }
        var begun = loggedWorkout
        begun.count = nil
        guard let set = currentSet else { return begun }
        let clock = loggedWorkout.clock(at: now)
        var lead = workout.startIn(before: set)
        var base = loggedWorkout.tick(nearest: now)
        var restJustEnded = false
        if let rest = rest(override: restOverride) {
            guard rest.isOver(atClock: clock) else { return begun }
            restJustEnded = clock - rest.leaveClock <= Self.missedBy
            if restJustEnded {
                base = rest.leaveClock
            }
        }
        if !restJustEnded, lead == 0, isOnTimedSet {
            lead = Self.startIn
        }
        if lead > 0 {
            lead += Int(Self.startInHold)
        }
        guard lead > 0 || isOnTimedSet else { return begun }
        begun.count = SetCount(set: set, startClock: base + Double(lead))
        return clock < 0 ? Self.timeStartingAtCount(begun) : begun
    }

    /// The workout with `set`, a set of `row`, logged at `now`. A set with a count logs the time
    /// done, its +15 s taps, and, when it ran out, the clock and the time of day at its end, so
    /// the rest after it starts where the set ended, and the set reads as done then, however
    /// late it is noticed. The end's time of day is the clock's at the end, read as if no pause
    /// was resumed since: a count can't end in a pause, and the gap to its log is time away from
    /// the count, the phone locked or the app gone, so a pause resumed inside it isn't expected;
    /// one would put the time of day late by its length. The key takes no log during a set's
    /// "Start in" (`WorkoutPhase.takesLog`). The next set's count is not begun here: with no rest
    /// before it, its
    /// "Start in" begins as the screen lands on it, so all of it is seen
    /// (`beginningCount(at:restOverride:fresh:)`).
    public func logging(_ set: PlannedSet, of row: WorkoutExercise, at now: Date) -> LoggedWorkout {
        let clock = loggedWorkout.clock(at: now)
        let timed = timedSet.flatMap { $0.set == set ? $0 : nil }
        let endClock = timed.flatMap { $0.isOver(atClock: clock) ? $0.endClock : nil }
        var logged = loggedWorkout.logging(
            set,
            of: row,
            at: endClock.map(loggedWorkout.date(ofClock:)) ?? now,
        )
        guard logged.sets.count > loggedWorkout.sets.count else { return loggedWorkout }
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
    /// at the time done, as a log at that moment logs it, and one whose count ran out at its full
    /// time. A timed set still in "Start in" logs nothing: it never began. Paused, the set is
    /// logged as the pause began, where its count stopped, so its time of day and its clock agree.
    public func finishing(at now: Date) -> LoggedWorkout {
        guard countStage(at: now) == .counting, let timed = timedSet, let row = currentExercise
        else { return loggedWorkout.finishing(at: now) }
        return logging(timed.set, of: row, at: loggedWorkout.pausedAt ?? now).finishing(at: now)
    }

    /// The workout with `seconds` added to the set counting, as a +15 s tap does. Unchanged
    /// during "Start in" or once over, so a tap landing as it ends brings nothing back.
    public func extendingCount(by seconds: Int, at now: Date) -> LoggedWorkout {
        let clock = loggedWorkout.clock(at: now)
        guard loggedWorkout.isInProgress, let timed = timedSet, timed.startIn(atClock: clock) == 0,
              !timed.isOver(atClock: clock)
        else { return loggedWorkout }
        var extended = loggedWorkout
        extended.count?.added += seconds
        return extended
    }

    /// The workout as a screen opening at `now` finds it: a count that ran out meanwhile
    /// logged at its full time, then the next set's count begun. One set, never a chain.
    public func caughtUp(at now: Date, restOverride: Int? = nil) -> LoggedWorkout {
        var live = self
        if let timed = timedSet, timed.isOver(atClock: loggedWorkout.clock(at: now)),
           let row = currentExercise
        {
            live = LiveWorkout(
                workout: workout,
                loggedWorkout: logging(timed.set, of: row, at: now),
            )
        }
        return live.beginningCount(at: now, restOverride: restOverride)
    }
}
