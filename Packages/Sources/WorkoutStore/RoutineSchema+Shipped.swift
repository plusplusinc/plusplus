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

/// As #91 shipped it, with `openedAt`, before workouts, and as #97 and #127 kept its routines.
enum RoutineSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] {
        [StoredRoutine.self, StoredRoutineExercise.self]
    }

    @Model
    final class StoredRoutine {
        var id = UUID()
        /// Empty when unnamed.
        var name = ""
        /// When the name or the rows last changed: the launch rule opens the latest.
        var editedAt = Date.distantPast
        /// When the routine was last opened from the drawer. Apart from `editedAt`, so an open is
        /// never mistaken for an edit; a routine's recency is the later of the two.
        var openedAt = Date.distantPast
        /// When the routine was last used: opened or edited, whichever came later.
        var recency: Date {
            max(editedAt, openedAt)
        }

        @Relationship(deleteRule: .cascade, inverse: \StoredRoutineExercise.routine)
        var exercises: [StoredRoutineExercise]? = []

        init(id: UUID) {
            self.id = id
        }
    }

    @Model
    final class StoredRoutineExercise {
        /// The row's own identity, so duplicates of an exercise stay apart.
        var id = UUID()
        /// The built-in exercise's slug, `Exercise.id`.
        var exerciseID = ""
        /// A relationship is unordered, so the row carries its place.
        var position = 0
        var routine: StoredRoutine?
        // The row's plan. Nil means never stored, read as the exercise's default: rows saved before
        // plans existed have none. Reps and seconds are apart so a stored number never changes
        // meaning if an exercise's measure does.
        var sets: Int?
        var reps: Int?
        var seconds: Int?
        var weight: Double?
        /// `WeightUnit`'s raw value; set with `weight`, or both nil.
        var weightUnit: String?
        /// The superset the row is in, shared with the rows next to it in it; nil for a plain row,
        /// and for every row saved before supersets.
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
        [
            RoutineSchemaV4.StoredRoutine.self,
            RoutineSchemaV4.StoredRoutineExercise.self,
            StoredWorkout.self,
        ]
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
