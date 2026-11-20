import Foundation

/// A workout: a routine being done, from Start to Finish. Running, paused, and finished follow
/// from its dates, so there is no state to fall out of step with them. Every change takes the
/// moment it happens, `now`, so the clock is the caller's.
public struct Workout: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// The routine it runs. An id, not the routine, so deleting the routine leaves the workout.
    public var routineID: UUID
    /// The routine's name, written at Start and again at Finish, so a rename or delete after it
    /// ends leaves the workout as it was.
    public var routineName: String
    public var startedAt: Date
    /// When the pause in progress began; nil while running.
    public var pausedAt: Date?
    /// The length of every pause already resumed.
    public var pausedSeconds: Double
    /// When it finished; nil while in progress.
    public var endedAt: Date?
    /// Every set done in it, in the order logged.
    public var sets: [LoggedSet]
    /// The timed set whose turn has come, until it is logged; nil for none.
    public var count: SetCount?

    public init(
        id: UUID = UUID(),
        routineID: UUID,
        routineName: String,
        startedAt: Date,
        pausedAt: Date? = nil,
        pausedSeconds: Double = 0,
        endedAt: Date? = nil,
        sets: [LoggedSet] = [],
        count: SetCount? = nil,
    ) {
        self.count = count
        self.id = id
        self.routineID = routineID
        self.routineName = routineName
        self.startedAt = startedAt
        self.pausedAt = pausedAt
        self.pausedSeconds = pausedSeconds
        self.endedAt = endedAt
        self.sets = sets
    }

    public var isPaused: Bool {
        pausedAt != nil && endedAt == nil
    }

    public var isInProgress: Bool {
        endedAt == nil
    }

    /// Whether ending it offers to finish and keep it: only once a set is done, and while it is
    /// in progress. Otherwise there is nothing to keep, and it can only be discarded.
    public var offersFinish: Bool {
        isInProgress && !sets.isEmpty
    }

    /// The time spent working out at `now`, pauses left out, in whole seconds rounded down.
    /// Fixed once paused or finished; never below zero, as with a clock set back.
    public func elapsed(at now: Date) -> Duration {
        .seconds(clock(at: now).rounded(.down))
    }

    /// The seconds spent working out at `now`, pauses left out, not rounded: the clock a rest
    /// runs on, so a pause stops it. Never below zero.
    public func clock(at now: Date) -> Double {
        let end = endedAt ?? pausedAt ?? now
        return max(0, end.timeIntervalSince(startedAt) - pausedSeconds)
    }

    /// When the clock reads `clock`, while it runs on from now with no pause.
    public func date(ofClock clock: Double) -> Date {
        clockStart.addingTimeInterval(clock)
    }

    /// When the elapsed time last stood at zero, as if there had been no pauses: whole seconds
    /// of the elapsed time fall on whole seconds from here, so a clock can tick on them.
    public var clockStart: Date {
        startedAt.addingTimeInterval(pausedSeconds)
    }

    /// Paused at `now`; unchanged if already paused or finished.
    public func pausing(at now: Date) -> Self {
        guard isInProgress, pausedAt == nil else { return self }
        var paused = self
        paused.pausedAt = now
        return paused
    }

    /// Running again, the pause added to the time paused; unchanged if not paused.
    public func resuming(at now: Date) -> Self {
        guard isInProgress, let pausedAt else { return self }
        var resumed = self
        resumed.pausedSeconds += max(0, now.timeIntervalSince(pausedAt))
        resumed.pausedAt = nil
        return resumed
    }

    /// With `planned` logged at `now`, at the numbers `row` plans now, done as planned.
    public func logging(_ planned: PlannedSet, of row: RoutineExercise, at now: Date) -> Self {
        // Once only: a log from a view built before the last one, or a second action, keeps one.
        guard !sets.contains(where: { $0.planned == planned }) else { return self }
        var logged = self
        logged.sets.append(LoggedSet(
            row: row.id,
            exerciseID: row.exercise.id,
            exerciseName: row.exercise.name,
            round: planned.round,
            side: planned.side,
            target: row.plan.target,
            weight: row.shownWeight,
            plannedTarget: row.plan.target,
            plannedWeight: row.shownWeight,
            loggedAt: now,
        ))
        logged.sets[logged.sets.count - 1].clockWhenLogged = clock(at: now)
        return logged
    }

    /// Finished at `now`, a pause in progress counting as paused; unchanged if already finished.
    public func finishing(at now: Date) -> Self {
        guard isInProgress else { return self }
        var finished = resuming(at: now)
        finished.endedAt = now
        return finished
    }
}
