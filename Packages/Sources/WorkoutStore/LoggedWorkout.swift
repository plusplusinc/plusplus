import Foundation

/// A logged workout: one time through a workout, from Start to Finish. Running, paused, and
/// finished follow from its dates, so there is no state to fall out of step with them. Every change
/// takes the moment it happens, `now`, so the clock is the caller's.
public struct LoggedWorkout: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// The workout it runs. An id, not the workout, so deleting the workout leaves this one.
    public var workoutID: UUID
    /// The workout's name, written at Start and again at Finish, so a rename or delete after it
    /// ends leaves the logged workout as it was.
    public var workoutName: String
    public var startedAt: Date
    /// When the pause in progress began; nil while running.
    public var pausedAt: Date?
    /// The length of every pause already resumed.
    public var pausedSeconds: Double
    /// Every pause already resumed, from when it began to when it ended, in order; a pause in
    /// progress at Finish is one. Empty for those resumed before the store kept their times
    /// (V14), whose length `pausedSeconds` still holds.
    public var pauses: [DateInterval]
    /// When it finished; nil while in progress.
    public var endedAt: Date?
    /// Every set done in it, in the order logged.
    public var sets: [LoggedSet]
    /// The timed set whose turn has come, until it is logged; nil for none.
    public var count: SetCount?
    /// Its type in Apple Health, worked out at Finish from what was done then; nil while in
    /// progress, and for a workout finished before the store kept it (V14).
    public var healthActivity: HealthActivity?
    /// The workout Apple Health saved for it; nil until one is. Only the store's own mark
    /// sets it, so a save of this value never clears it.
    public internal(set) var healthWorkoutID: UUID?

    public init(
        id: UUID = UUID(),
        workoutID: UUID,
        workoutName: String,
        startedAt: Date,
        pausedAt: Date? = nil,
        pausedSeconds: Double = 0,
        pauses: [DateInterval] = [],
        endedAt: Date? = nil,
        sets: [LoggedSet] = [],
        count: SetCount? = nil,
        healthActivity: HealthActivity? = nil,
    ) {
        self.count = count
        self.id = id
        self.workoutID = workoutID
        self.workoutName = workoutName
        self.startedAt = startedAt
        self.pausedAt = pausedAt
        self.pausedSeconds = pausedSeconds
        self.pauses = pauses
        self.endedAt = endedAt
        self.sets = sets
        self.healthActivity = healthActivity
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
    /// Fixed once paused or finished; never below zero, as through the first set's "Start in"
    /// and with a clock set back.
    public func elapsed(at now: Date) -> Duration {
        .seconds(max(0, clock(at: now)).rounded(.down))
    }

    /// The seconds spent working out at `now`, pauses left out, not rounded: the clock a rest
    /// runs on, so a pause stops it. Below zero only before the workout's time starts, with
    /// nothing logged: through the first set's "Start in", which counts up to zero, where the
    /// set and the time begin (`LiveWorkout.landingStart(at:restOverride:)`). Once a set is
    /// logged, never below zero, as with a device clock set back.
    public func clock(at now: Date) -> Double {
        let end = endedAt ?? pausedAt ?? now
        let clock = end.timeIntervalSince(startedAt) - pausedSeconds
        return sets.isEmpty ? clock : max(0, clock)
    }

    /// The workout with its time starting at `now`, when it hasn't yet: the first set logged
    /// before the clock reaches zero. The key takes no log through "Start in", so only a log a
    /// moment ahead of the clock gets here. Unchanged once the time runs. A pause resumed
    /// before is dropped with the time before it: none of it is the workout's.
    public func startingClock(at now: Date) -> Self {
        guard isInProgress, clock(at: now) < 0 else { return self }
        var started = self
        started.startedAt = pausedAt ?? now
        started.pausedSeconds = 0
        started.pauses = []
        return started
    }

    /// The whole second of the clock nearest `now`, where a set's "Start in" begins, so it
    /// turns over on the same ticks as the workout's time: everything timed in a workout begins
    /// on a whole second of its clock. Up to half a second ahead of `now`, where "Start in"
    /// holds at its full count; its first second so runs from half a second to one and a half.
    public func tick(nearest now: Date) -> Double {
        clock(at: now).rounded()
    }

    /// The whole second of the clock at or before `now`, where what is in effect at once
    /// begins: the rest at a set's log, and the next set's count at Skip rest.
    /// Never ahead of `now`, so nothing reads it as not yet begun; its first second runs short.
    public func tick(before now: Date) -> Double {
        clock(at: now).rounded(.down)
    }

    /// When the clock reads `clock`, while it runs on from now with no pause.
    public func date(ofClock clock: Double) -> Date {
        clockStart.addingTimeInterval(clock)
    }

    /// When the elapsed time next turns over after `now`: its next whole second, on the clock
    /// as it runs on from now with no pause.
    public func nextSecond(after now: Date) -> Date {
        date(ofClock: clock(at: now).rounded(.down) + 1)
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

    /// Running again, the pause added to the time paused and kept with its times; unchanged if
    /// not paused.
    public func resuming(at now: Date) -> Self {
        guard isInProgress, let pausedAt else { return self }
        var resumed = self
        let pause = DateInterval(start: pausedAt, end: max(now, pausedAt))
        resumed.pausedSeconds += pause.duration
        resumed.pauses.append(pause)
        resumed.pausedAt = nil
        return resumed
    }

    /// With `planned` logged at `now`, at the numbers `row` plans now, done as planned.
    public func logging(_ planned: PlannedSet, of row: WorkoutExercise, at now: Date) -> Self {
        // Once only: a log from a view built before the last one, or a second action, keeps one.
        guard !sets.contains(where: { $0.planned == planned }) else { return self }
        // The first set logged before the time has started: it starts at the log.
        var logged = startingClock(at: now)
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
        logged.sets[logged.sets.count - 1].clockWhenLogged = logged.tick(before: now)
        return logged
    }

    /// Finished at `now`, a pause in progress counting as paused, with no count kept. A set
    /// counting is logged first by `LiveWorkout.finishing(at:)`, which knows its row, and is the
    /// one way to finish from outside the package; here it is dropped. Unchanged if already
    /// finished.
    func finishing(at now: Date) -> Self {
        guard isInProgress else { return self }
        var finished = resuming(at: now)
        finished.endedAt = now
        finished.count = nil
        return finished
    }
}
