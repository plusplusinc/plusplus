import SwiftData

/// Every stored shape the app has shipped, oldest first, and a lightweight stage between each,
/// but for the two that move rows to a renamed model (`moveSessions`, `moveWorkouts`):
/// SwiftData can't rename a model, and a rename by inference drops its rows with no error.
enum StoreMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            RoutineSchemaV1.self,
            RoutineSchemaV2.self,
            RoutineSchemaV3.self,
            RoutineSchemaV4.self,
            RoutineSchemaV5.self,
            RoutineSchemaV6.self,
            RoutineSchemaV7.self,
            RoutineSchemaV8.self,
            RoutineSchemaV9.self,
            RoutineSchemaV10.self,
            RoutineSchemaV11.self,
            RoutineSchemaV12.self,
            RoutineSchemaV13.self,
            RoutineSchemaV14.self,
            StoreSchemaV15.self,
            StoreSchemaV16.self,
            StoreSchemaV17.self,
        ]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: RoutineSchemaV1.self, toVersion: RoutineSchemaV2.self),
            .lightweight(fromVersion: RoutineSchemaV2.self, toVersion: RoutineSchemaV3.self),
            .lightweight(fromVersion: RoutineSchemaV3.self, toVersion: RoutineSchemaV4.self),
            .lightweight(fromVersion: RoutineSchemaV4.self, toVersion: RoutineSchemaV5.self),
            .lightweight(fromVersion: RoutineSchemaV5.self, toVersion: RoutineSchemaV6.self),
            .lightweight(fromVersion: RoutineSchemaV6.self, toVersion: RoutineSchemaV7.self),
            .lightweight(fromVersion: RoutineSchemaV7.self, toVersion: RoutineSchemaV8.self),
            .lightweight(fromVersion: RoutineSchemaV8.self, toVersion: RoutineSchemaV9.self),
            .lightweight(fromVersion: RoutineSchemaV9.self, toVersion: RoutineSchemaV10.self),
            .lightweight(fromVersion: RoutineSchemaV10.self, toVersion: RoutineSchemaV11.self),
            .lightweight(fromVersion: RoutineSchemaV11.self, toVersion: RoutineSchemaV12.self),
            .lightweight(fromVersion: RoutineSchemaV12.self, toVersion: RoutineSchemaV13.self),
            .lightweight(fromVersion: RoutineSchemaV13.self, toVersion: RoutineSchemaV14.self),
            .lightweight(fromVersion: RoutineSchemaV14.self, toVersion: StoreSchemaV15.self),
            .custom(
                fromVersion: StoreSchemaV15.self,
                toVersion: StoreSchemaV16.self,
                willMigrate: moveSessions(in:),
                didMigrate: nil,
            ),
            .custom(
                fromVersion: StoreSchemaV16.self,
                toVersion: StoreSchemaV17.self,
                willMigrate: moveWorkouts(in:),
                didMigrate: nil,
            ),
        ]
    }

    /// The current shape, the plan's last.
    static let current = StoreSchemaV17.self
}
