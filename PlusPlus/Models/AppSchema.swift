import Foundation
import SwiftData

/// The versioned SwiftData schema and its migration plan (#155).
///
/// Until build 74 the app opened a plain `Schema([...])` and, on ANY
/// open failure, DESTROYED and recreated the store (the #153 beta
/// stopgap). That silently drops training history the moment real usage
/// or sync ships. This file establishes the 1.0 policy:
///
/// - A `VersionedSchema` per shape (starting at V1 = today's entities)
///   plus a `SchemaMigrationPlan`, so a future shape change MIGRATES the
///   store instead of resetting it (an entity rename like #144 no longer
///   bricks a store).
/// - The container opens WITH the plan (`PlusPlusApp`). Recovery only
///   fires when opening is genuinely impossible (corruption, an unknown
///   store), and even then it copies the raw store aside first — never a
///   silent wipe (`StoreRecovery`).
///
/// V1 lists the LIVE model types directly: it *is* the current shape, so
/// no snapshot duplication is needed yet. **When a later version changes
/// a model, FREEZE V1 into standalone snapshot classes here** (the live
/// classes become the newer version's `models`) so V1 keeps describing
/// the pre-change shape — each `VersionedSchema` is a complete snapshot,
/// not a diff (the Axiom/Apple rule).
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
/// stages arrive with the first shape change. `schemas` is in upgrade
/// order, oldest first.
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
