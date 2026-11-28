import Foundation
import OSLog
import SwiftData

/// The stored shape of a time through a workout, `WorkoutSession`, and of its sets. The class
/// names will be CloudKit record types once sync is on.
typealias StoredWorkoutSession = StoreSchemaV15.StoredWorkoutSession
typealias StoredLoggedSet = StoreSchemaV15.StoredLoggedSet

extension StoredWorkoutSession {
    /// Writes every field, setting only those that differ, so an unchanged session stays clean.
    /// Its sets are written by the store, which diffs them by id.
    func write(_ workoutSession: WorkoutSession) {
        update(\.workoutID, to: workoutSession.workoutID)
        update(\.workoutName, to: workoutSession.workoutName)
        update(\.startedAt, to: workoutSession.startedAt)
        update(\.pausedAt, to: workoutSession.pausedAt)
        update(\.pausedSeconds, to: workoutSession.pausedSeconds)
        update(\.endedAt, to: workoutSession.endedAt)
        update(\.countRowID, to: workoutSession.count?.set.row)
        update(\.countRound, to: workoutSession.count?.set.round)
        update(\.countSide, to: workoutSession.count?.set.side?.rawValue)
        update(\.countStartClock, to: workoutSession.count?.startClock)
        update(\.countAdded, to: workoutSession.count?.added ?? 0)
        // A stored pause list or type it couldn't read, as from a newer version, read as none
        // and is left as it is, as `healthWorkoutID` is, unless the workout now has its own.
        if !workoutSession.pauses.isEmpty || pauses != nil {
            let pauseTimes = workoutSession.pauses.flatMap { [$0.start, $0.end] }
            update(\.pauseTimes, to: pauseTimes.isEmpty ? nil : pauseTimes)
        }
        if workoutSession.healthActivity != nil || !holdsUnreadActivity {
            update(\.healthActivity, to: workoutSession.healthActivity?.rawValue)
        }
        // Not `healthWorkoutID`: only `Store.markInHealth` writes it, so a save from a copy
        // read before it was kept never clears it.
    }

    /// Whether the stored type is one this version doesn't know.
    private var holdsUnreadActivity: Bool {
        healthActivity.map { HealthActivity(rawValue: $0) == nil } ?? false
    }

    /// Each kept pause, none when nothing is stored; nil when the stored times don't pair
    /// up, each pause's start at or before its end. Their order across pauses is
    /// `WorkoutSession.healthWithheld`'s to judge.
    private var pauses: [DateInterval]? {
        guard let pauseTimes else { return [] }
        guard pauseTimes.count.isMultiple(of: 2) else { return nil }
        let pairs = stride(from: 0, to: pauseTimes.count, by: 2).map {
            (pauseTimes[$0], pauseTimes[$0 + 1])
        }
        guard pairs.allSatisfy({ $0 <= $1 }) else { return nil }
        return pairs.map { DateInterval(start: $0, end: $1) }
    }

    /// The count under way, when its row, round, and start clock are all stored.
    private var count: SetCount? {
        guard let countRowID, let countRound, let countStartClock else { return nil }
        let set = PlannedSet(
            row: countRowID,
            round: countRound,
            side: countSide.flatMap(Side.init(rawValue:)),
        )
        return SetCount(set: set, startClock: countStartClock, added: countAdded)
    }

    /// The logged workout, its sets in the order logged; a set it can't read is left out.
    var workoutSession: WorkoutSession {
        var workoutSession = WorkoutSession(
            id: id,
            workoutID: workoutID ?? UUID(),
            workoutName: workoutName,
            startedAt: startedAt,
            pausedAt: pausedAt,
            pausedSeconds: pausedSeconds,
            pauses: pauses ?? [],
            endedAt: endedAt,
            sets: (sets ?? []).sorted { $0.position < $1.position }.compactMap(\.loggedSet),
            count: count,
            healthActivity: healthActivity.flatMap(HealthActivity.init(rawValue:)),
        )
        workoutSession.healthWorkoutID = healthWorkoutID
        return workoutSession
    }
}

extension StoredLoggedSet {
    /// Writes every field of `set`, logged `position`th, setting only those that differ.
    func write(_ set: LoggedSet, position: Int) {
        update(\.rowID, to: set.row)
        update(\.exerciseID, to: set.exerciseID)
        update(\.exerciseName, to: set.exerciseName)
        update(\.position, to: position)
        update(\.round, to: set.round)
        update(\.side, to: set.side?.rawValue)
        let done = Self.fields(set.target, set.weight)
        update(\.reps, to: done.reps)
        update(\.seconds, to: done.seconds)
        update(\.weight, to: done.weight)
        update(\.weightUnit, to: done.unit)
        let planned = Self.fields(set.plannedTarget, set.plannedWeight)
        update(\.plannedReps, to: planned.reps)
        update(\.plannedSeconds, to: planned.seconds)
        update(\.plannedWeight, to: planned.weight)
        update(\.plannedWeightUnit, to: planned.unit)
        update(\.loggedAt, to: set.loggedAt)
        update(\.clockWhenLogged, to: set.clockWhenLogged)
        update(\.restAdjustment, to: set.restAdjustment)
        update(\.timeAdded, to: set.timeAdded)
        update(\.restSkippedAt, to: set.restSkippedAt)
    }

    /// A set's reps or time and weight, as the stored fields hold them.
    private struct Fields {
        var reps: Int?
        var seconds: Int?
        var weight: Double?
        var unit: String?
    }

    private static func fields(_ target: SetTarget, _ weight: Weight?) -> Fields {
        var fields = Fields(weight: weight?.amount, unit: weight?.unit.rawValue)
        switch target {
        case let .reps(count): fields.reps = count
        case let .time(time): fields.seconds = time
        }
        return fields
    }

    /// Whether the set reads as a logged set: it has a row, and reps or a time, done and planned.
    var isReadable: Bool {
        rowID != nil && Self.storedTarget(reps, seconds) != nil
            && Self.storedTarget(plannedReps, plannedSeconds) != nil
    }

    /// The set, or nil, logged, when it has no row or no reps or time to read.
    var loggedSet: LoggedSet? {
        guard let rowID,
              let target = Self.storedTarget(reps, seconds),
              let plannedTarget = Self.storedTarget(plannedReps, plannedSeconds)
        else {
            Logger.storage.error("Skipped a logged set with no row or no reps or time")
            return nil
        }
        var set = LoggedSet(
            id: id,
            row: rowID,
            exerciseID: exerciseID,
            exerciseName: exerciseName,
            round: round,
            side: side.flatMap(Side.init(rawValue:)),
            target: target,
            weight: Self.storedWeight(weight, weightUnit),
            plannedTarget: plannedTarget,
            plannedWeight: Self.storedWeight(plannedWeight, plannedWeightUnit),
            loggedAt: loggedAt,
        )
        set.clockWhenLogged = clockWhenLogged
        set.restAdjustment = restAdjustment
        set.timeAdded = timeAdded
        set.restSkippedAt = restSkippedAt
        return set
    }

    private static func storedTarget(_ reps: Int?, _ seconds: Int?) -> SetTarget? {
        reps.map(SetTarget.reps) ?? seconds.map { .time(seconds: $0) }
    }

    private static func storedWeight(_ amount: Double?, _ unit: String?) -> Weight? {
        guard let amount, let unit = unit.flatMap(WeightUnit.init(rawValue:)) else { return nil }
        return Weight(amount, unit)
    }
}
