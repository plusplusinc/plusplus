import Foundation
import SwiftData

typealias StoredWorkout = RoutineSchemaV5.StoredWorkout

/// Today's routines and workouts.
enum RoutineSchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)
    static var models: [any PersistentModel.Type] {
        [StoredRoutine.self, StoredRoutineExercise.self, StoredWorkout.self]
    }

    /// The stored shape of a workout. Its routine is an id, not a relationship, so deleting the
    /// routine leaves the workout. No status: running, paused, and finished follow from the
    /// dates, and a discarded workout is deleted.
    @Model
    final class StoredWorkout {
        var id = UUID()
        var routineID: UUID?
        var routineName = ""
        var startedAt = Date.distantPast
        var pausedAt: Date?
        var pausedSeconds = 0.0
        var endedAt: Date?

        init(id: UUID) {
            self.id = id
        }
    }
}

extension StoredWorkout {
    /// Writes every field, setting only those that differ, so an unchanged workout stays clean.
    func write(_ workout: Workout) {
        update(\.routineID, to: workout.routineID)
        update(\.routineName, to: workout.routineName)
        update(\.startedAt, to: workout.startedAt)
        update(\.pausedAt, to: workout.pausedAt)
        update(\.pausedSeconds, to: workout.pausedSeconds)
        update(\.endedAt, to: workout.endedAt)
    }

    var workout: Workout {
        Workout(
            id: id,
            routineID: routineID ?? UUID(),
            routineName: routineName,
            startedAt: startedAt,
            pausedAt: pausedAt,
            pausedSeconds: pausedSeconds,
            endedAt: endedAt,
        )
    }

    private func update<Value: Equatable>(
        _ field: ReferenceWritableKeyPath<StoredWorkout, Value>,
        to value: Value,
    ) {
        if self[keyPath: field] != value {
            self[keyPath: field] = value
        }
    }
}
