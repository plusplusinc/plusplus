import Foundation
import SwiftData

/// The versioned SwiftData schema and its migration plan (#155).
///
/// Until build 74 the app opened a plain `Schema([...])` and, on ANY open
/// failure, DESTROYED and recreated the store (the #153 beta stopgap). This
/// establishes the 1.0 policy: a `VersionedSchema` + `SchemaMigrationPlan`
/// so a future shape change MIGRATES the store instead of resetting it, and
/// recovery that copies the store aside rather than wiping it silently
/// (`StoreRecovery`, `PlusPlusApp`).
///
/// V1 lists the LIVE model types directly — it *is* the current shape. The
/// routine-family `uuid` (for the tray-flicker decoupling) is an OPTIONAL
/// additive column, which SwiftData migrates in automatically (lightweight):
/// an existing store's rows get `nil`, and `SeedData.backfillModelUUIDsIfNeeded`
/// assigns each a value at launch. Deliberately NOT modeled as a V1→V2 custom
/// stage with a frozen V1 snapshot: nested snapshot `@Model` classes that
/// coexist with the live top-level classes of the same entity name crash
/// migration with a `Failed to cast model` fatal error — the lightweight +
/// launch-backfill path is the robust way to add this field. **When a future
/// change genuinely needs a custom transform, add a new `VersionedSchema` +
/// `MigrationStage` here** (freezing V1 into snapshots only if that change
/// can't ride lightweight).
enum AppSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Routine.self, RoutineExercise.self, ExerciseGroup.self,
            Exercise.self, Equipment.self, EquipmentLibrary.self,
            WorkoutSession.self, SetLog.self,
        ]
    }
}

/// The migration plan the container opens with. One schema today (V1);
/// stages arrive with the first change lightweight can't express.
enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [AppSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

/// The schema the app opens against — always the latest version. Kept as
/// one named accessor so `PlusPlusApp` and the migration tests build the
/// identical schema.
enum AppSchema {
    static var latest: Schema { Schema(versionedSchema: AppSchemaV1.self) }
}
