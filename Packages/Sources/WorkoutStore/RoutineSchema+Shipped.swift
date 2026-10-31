import Foundation
import SwiftData

// The stored shapes earlier versions shipped, kept so the migration plan can name them: staged
// migration refuses a store whose model matches none of the plan's versions. Each holds only the
// attributes it shipped with, under the same entity names. Never change one; a new shape is a
// new version.

/// As #68 shipped it, before rows held plans.
enum RoutineSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [StoredRoutine.self, StoredRoutineExercise.self]
    }

    @Model
    final class StoredRoutine {
        var id = UUID()
        var name = ""
        var editedAt = Date.distantPast
        @Relationship(deleteRule: .cascade, inverse: \StoredRoutineExercise.routine)
        var exercises: [StoredRoutineExercise]? = []

        init(id: UUID) {
            self.id = id
        }
    }

    @Model
    final class StoredRoutineExercise {
        var id = UUID()
        var exerciseID = ""
        var position = 0
        var routine: StoredRoutine?

        init(id: UUID, exerciseID: String, position: Int) {
            self.id = id
            self.exerciseID = exerciseID
            self.position = position
        }
    }
}

/// As #70 shipped it, with plans and before supersets.
enum RoutineSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [StoredRoutine.self, StoredRoutineExercise.self]
    }

    @Model
    final class StoredRoutine {
        var id = UUID()
        var name = ""
        var editedAt = Date.distantPast
        @Relationship(deleteRule: .cascade, inverse: \StoredRoutineExercise.routine)
        var exercises: [StoredRoutineExercise]? = []

        init(id: UUID) {
            self.id = id
        }
    }

    @Model
    final class StoredRoutineExercise {
        var id = UUID()
        var exerciseID = ""
        var position = 0
        var routine: StoredRoutine?
        var sets: Int?
        var reps: Int?
        var seconds: Int?
        var weight: Double?
        var weightUnit: String?

        init(id: UUID, exerciseID: String, position: Int) {
            self.id = id
            self.exerciseID = exerciseID
            self.position = position
        }
    }
}

/// As #85 shipped it, with supersets and before routines were opened.
enum RoutineSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] {
        [StoredRoutine.self, StoredRoutineExercise.self]
    }

    @Model
    final class StoredRoutine {
        var id = UUID()
        var name = ""
        var editedAt = Date.distantPast
        @Relationship(deleteRule: .cascade, inverse: \StoredRoutineExercise.routine)
        var exercises: [StoredRoutineExercise]? = []

        init(id: UUID) {
            self.id = id
        }
    }

    @Model
    final class StoredRoutineExercise {
        var id = UUID()
        var exerciseID = ""
        var position = 0
        var routine: StoredRoutine?
        var sets: Int?
        var reps: Int?
        var seconds: Int?
        var weight: Double?
        var weightUnit: String?
        var supersetID: UUID?

        init(id: UUID, exerciseID: String, position: Int) {
            self.id = id
            self.exerciseID = exerciseID
            self.position = position
        }
    }
}

/// As #97 shipped it, with workouts and before logged sets. Its routines are still today's.
enum RoutineSchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)
    static var models: [any PersistentModel.Type] {
        [StoredRoutine.self, StoredRoutineExercise.self, StoredWorkout.self]
    }

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
