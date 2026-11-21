import Foundation
import OSLog
import SwiftData

typealias StoredWorkout = RoutineSchemaV12.StoredWorkout
typealias StoredSet = RoutineSchemaV12.StoredSet

/// As #127 shipped it, with logged sets, its routines still V4's.
enum RoutineSchemaV6: VersionedSchema {
    static let versionIdentifier = Schema.Version(6, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            RoutineSchemaV4.StoredRoutine.self,
            RoutineSchemaV4.StoredRoutineExercise.self,
            StoredWorkout.self,
            StoredSet.self,
        ]
    }

    /// The stored shape of a workout. Its routine is an id, not a relationship, so deleting the
    /// routine leaves the workout. No status: running, paused, and finished follow from the
    /// dates, and a discarded workout is deleted, its sets with it.
    @Model
    final class StoredWorkout {
        var id = UUID()
        var routineID: UUID?
        var routineName = ""
        var startedAt = Date.distantPast
        var pausedAt: Date?
        var pausedSeconds = 0.0
        var endedAt: Date?
        @Relationship(deleteRule: .cascade, inverse: \StoredSet.workout)
        var sets: [StoredSet]? = []

        init(id: UUID) {
            self.id = id
        }
    }

    /// A set done in a workout: its numbers as done, and as planned, apart. Its row is an id, and
    /// its exercise a slug, so a set reads the same once its row is deleted.
    @Model
    final class StoredSet {
        var id = UUID()
        var workout: StoredWorkout?
        var rowID: UUID?
        /// The exercise's `Exercise.id`, a built-in's slug or a created exercise's id.
        var exerciseID = ""
        /// The order it was logged in: a relationship is unordered.
        var position = 0
        var round = 0
        /// `Side`'s raw value; nil for an exercise not done per side, and an unknown one reads
        /// as nil.
        var side: String?
        // As done. Reps and seconds are apart, as on a row, so a number never changes meaning.
        var reps: Int?
        var seconds: Int?
        var weight: Double?
        /// `WeightUnit`'s raw value; set with `weight`, or both nil.
        var weightUnit: String?
        // As planned when it was logged.
        var plannedReps: Int?
        var plannedSeconds: Int?
        var plannedWeight: Double?
        var plannedWeightUnit: String?
        var loggedAt = Date.distantPast

        init(id: UUID) {
            self.id = id
        }
    }
}

extension StoredWorkout {
    /// Writes every field, setting only those that differ, so an unchanged workout stays clean.
    /// Its sets are written by the store, which diffs them by id.
    func write(_ workout: Workout) {
        update(\.routineID, to: workout.routineID)
        update(\.routineName, to: workout.routineName)
        update(\.startedAt, to: workout.startedAt)
        update(\.pausedAt, to: workout.pausedAt)
        update(\.pausedSeconds, to: workout.pausedSeconds)
        update(\.endedAt, to: workout.endedAt)
        update(\.countRowID, to: workout.count?.set.row)
        update(\.countRound, to: workout.count?.set.round)
        update(\.countSide, to: workout.count?.set.side?.rawValue)
        update(\.countStartClock, to: workout.count?.startClock)
        update(\.countAdded, to: workout.count?.added ?? 0)
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

    /// The workout, its sets in the order logged; a set it can't read is left out.
    var workout: Workout {
        Workout(
            id: id,
            routineID: routineID ?? UUID(),
            routineName: routineName,
            startedAt: startedAt,
            pausedAt: pausedAt,
            pausedSeconds: pausedSeconds,
            endedAt: endedAt,
            sets: (sets ?? []).sorted { $0.position < $1.position }.compactMap(\.loggedSet),
            count: count,
        )
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
