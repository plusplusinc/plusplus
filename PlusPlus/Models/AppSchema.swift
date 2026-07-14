import Foundation
import SwiftData

/// Schema **V2** — adds a stable `uuid` to `Routine`, `ExerciseGroup`, and
/// `RoutineExercise` so presentation/navigation can key on it instead of
/// SwiftData's `persistentModelID` (which swaps temporary→permanent at a
/// fresh model's first save and flickers open sheets/pushes). This is the
/// LATEST schema, so it references the live model types directly; the
/// pre-`uuid` shape lives frozen in `AppSchemaV1`.
enum AppSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Routine.self, ExerciseGroup.self, RoutineExercise.self,
            Exercise.self, Equipment.self, EquipmentLibrary.self,
            WorkoutSession.self, SetLog.self,
        ]
    }
}

/// The migration plan the container opens with (#155). `schemas` is in
/// upgrade order, oldest first. Opening WITH the plan is what lets a shape
/// change migrate the store instead of resetting it.
enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [AppSchemaV1.self, AppSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    /// V1 → V2: `uuid` is added as an OPTIONAL column (a non-optional UUID
    /// has no static default, so existing rows would fail validation on the
    /// add). Existing rows migrate to nil; this `.custom` stage's
    /// `didMigrate` then assigns a fresh, unique `uuid` per row. A defensive
    /// launch backfill (`SeedData.backfillModelUUIDsIfNeeded`) covers the
    /// plan-less-fallback open path, which skips migration stages. Runs only
    /// on a real V1→V2 upgrade; fresh installs create at V2 with init-minted
    /// uuids and never hit it.
    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: AppSchemaV1.self,
        toVersion: AppSchemaV2.self,
        willMigrate: nil,
        didMigrate: { context in
            for routine in try context.fetch(FetchDescriptor<Routine>()) {
                routine.uuid = UUID()
            }
            for group in try context.fetch(FetchDescriptor<ExerciseGroup>()) {
                group.uuid = UUID()
            }
            for entry in try context.fetch(FetchDescriptor<RoutineExercise>()) {
                entry.uuid = UUID()
            }
            try context.save()
        }
    )
}

/// The schema the app opens against — always the latest version. Kept as
/// one named accessor so `PlusPlusApp` and the migration tests build the
/// identical schema.
enum AppSchema {
    static var latest: Schema { Schema(versionedSchema: AppSchemaV2.self) }
}
