import Foundation
import SwiftData
import PlusPlusKit

/// Frozen snapshot of schema **V1** — the app's shape BEFORE the routine
/// models gained a stable `uuid` (#155 / the tray-flicker decoupling).
///
/// Each `VersionedSchema` is a complete snapshot, not a diff, so migration
/// needs the pre-change classes to still exist. Only the models that
/// CHANGED (gained `uuid`) — `Routine`, `ExerciseGroup`, `RoutineExercise`
/// — plus the models that relationally REFERENCE them (`WorkoutSession` →
/// `Routine`, and `SetLog` → `WorkoutSession`) are snapshotted here. The
/// unchanged cluster (`Exercise`/`Equipment`/`EquipmentLibrary`) is
/// referenced by its LIVE type — it's identical in V1 and V2, so freezing
/// it would only add copy risk.
///
/// ⚠️ These MUST byte-match the shipped V1 stored shape (every property,
/// type, optionality, default, relationship inverse + delete rule). A
/// mismatch makes an existing store fail to map to V1 → recovery resets it.
/// Do NOT add computed helpers or methods here — only the persisted shape.
enum AppSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Routine.self, ExerciseGroup.self, RoutineExercise.self,
            WorkoutSession.self, SetLog.self,
            // Unchanged cluster — live types, identical across versions.
            Exercise.self, Equipment.self, EquipmentLibrary.self,
        ]
    }

    @Model
    final class Routine {
        var name: String
        var createdAt: Date
        var order: Int
        var restSeconds: Int = 90
        var notes: String?
        var scheduleData: Data?
        @Relationship(deleteRule: .cascade, inverse: \ExerciseGroup.routine)
        var groups: [ExerciseGroup] = []

        init(name: String, order: Int = 0, restSeconds: Int = 90, notes: String? = nil) {
            self.name = name
            self.createdAt = Date()
            self.order = order
            self.restSeconds = restSeconds
            self.notes = notes
        }
    }

    @Model
    final class ExerciseGroup {
        var routine: Routine?
        var order: Int
        var sets: Int
        var restSecondsOverride: Int?
        @Relationship(deleteRule: .cascade, inverse: \RoutineExercise.group)
        var exercises: [RoutineExercise] = []

        init(order: Int = 0, sets: Int = 3) {
            self.order = order
            self.sets = sets
        }
    }

    @Model
    final class RoutineExercise {
        var group: ExerciseGroup?
        var exercise: Exercise?
        var order: Int
        var weight: Double?
        var reps: Int?
        var repsUpper: Int?
        var durationSeconds: Int?
        var heartRateTargetData: Data?
        var extraTargetsData: Data?

        init(exercise: Exercise, order: Int = 0) {
            self.exercise = exercise
            self.order = order
        }
    }

    @Model
    final class WorkoutSession {
        var routine: Routine?
        var routineName: String
        var startedAt: Date
        var endedAt: Date?
        var sessionId: UUID = UUID()
        var restSeconds: Int = 90
        var runStartedAt: Date?
        var segmentStartedAt: Date?
        var accumulatedSeconds: Double = 0
        var cursorOrder: Int = 0
        var averageHeartRate: Int?
        var maxHeartRate: Int?
        @Relationship(deleteRule: .cascade, inverse: \SetLog.session)
        var setLogs: [SetLog] = []

        init(routine: Routine? = nil, routineName: String, startedAt: Date = Date(), restSeconds: Int = 90) {
            self.routine = routine
            self.routineName = routineName
            self.startedAt = startedAt
            self.restSeconds = restSeconds
        }
    }

    @Model
    final class SetLog {
        var session: WorkoutSession?
        var order: Int
        var groupIndex: Int
        var setNumber: Int
        var exercise: Exercise?
        var exerciseName: String
        var exerciseType: ExerciseType
        var metricsData: Data?
        var restSecondsOverride: Int?
        var targetWeight: Double?
        var targetRepsLower: Int?
        var targetRepsUpper: Int?
        var targetDuration: Int?
        var targetHeartRateData: Data?
        var extraTargetsData: Data?
        var actualWeight: Double?
        var actualReps: Int?
        var actualDuration: Int?
        var extraActualsData: Data?
        var completedAt: Date?

        init(
            order: Int,
            groupIndex: Int,
            setNumber: Int,
            exercise: Exercise? = nil,
            exerciseName: String,
            exerciseType: ExerciseType = .weightReps,
            targetWeight: Double? = nil,
            targetRepsLower: Int? = nil,
            targetRepsUpper: Int? = nil,
            targetDuration: Int? = nil,
            targetHeartRateData: Data? = nil
        ) {
            self.order = order
            self.groupIndex = groupIndex
            self.setNumber = setNumber
            self.exercise = exercise
            self.exerciseName = exerciseName
            self.exerciseType = exerciseType
            self.targetWeight = targetWeight
            self.targetRepsLower = targetRepsLower
            self.targetRepsUpper = targetRepsUpper
            self.targetDuration = targetDuration
            self.targetHeartRateData = targetHeartRateData
        }
    }
}
