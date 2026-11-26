import Foundation
import OSLog
import SwiftData

typealias StoredWorkout = RoutineSchemaV14.StoredWorkout
typealias StoredSet = RoutineSchemaV14.StoredSet

extension StoredWorkout {
    /// Writes every field, setting only those that differ, so an unchanged workout stays clean.
    /// Its sets are written by the store, which diffs them by id.
    func write(_ loggedWorkout: LoggedWorkout) {
        update(\.routineID, to: loggedWorkout.workoutID)
        update(\.routineName, to: loggedWorkout.workoutName)
        update(\.startedAt, to: loggedWorkout.startedAt)
        update(\.pausedAt, to: loggedWorkout.pausedAt)
        update(\.pausedSeconds, to: loggedWorkout.pausedSeconds)
        update(\.endedAt, to: loggedWorkout.endedAt)
        update(\.countRowID, to: loggedWorkout.count?.set.row)
        update(\.countRound, to: loggedWorkout.count?.set.round)
        update(\.countSide, to: loggedWorkout.count?.set.side?.rawValue)
        update(\.countStartClock, to: loggedWorkout.count?.startClock)
        update(\.countAdded, to: loggedWorkout.count?.added ?? 0)
        let pauseTimes = loggedWorkout.pauses.flatMap { [$0.start, $0.end] }
        update(\.pauseTimes, to: pauseTimes.isEmpty ? nil : pauseTimes)
        update(\.healthActivity, to: loggedWorkout.healthActivity?.rawValue)
        // Not `healthWorkoutID`: only the store's mark sets it, so a save from a copy read
        // before it never clears it.
    }

    /// Each kept pause, when the stored times pair up in order; none otherwise.
    private var pauses: [DateInterval] {
        guard let pauseTimes, pauseTimes.count.isMultiple(of: 2),
              zip(pauseTimes, pauseTimes.dropFirst()).allSatisfy({ $0 <= $1 })
        else { return [] }
        return stride(from: 0, to: pauseTimes.count, by: 2).map {
            DateInterval(start: pauseTimes[$0], end: pauseTimes[$0 + 1])
        }
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
    var loggedWorkout: LoggedWorkout {
        var loggedWorkout = LoggedWorkout(
            id: id,
            workoutID: routineID ?? UUID(),
            workoutName: routineName,
            startedAt: startedAt,
            pausedAt: pausedAt,
            pausedSeconds: pausedSeconds,
            pauses: pauses,
            endedAt: endedAt,
            sets: (sets ?? []).sorted { $0.position < $1.position }.compactMap(\.loggedSet),
            count: count,
            healthActivity: healthActivity.flatMap(HealthActivity.init(rawValue:)),
        )
        loggedWorkout.healthWorkoutID = healthWorkoutID
        return loggedWorkout
    }
}

extension StoredSet {
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
