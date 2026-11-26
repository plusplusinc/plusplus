import SwiftData

/// Every stored shape the app has shipped, oldest first, and a lightweight stage between each,
/// since every change so far only added an attribute or a model.
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
        ]
    }

    /// The current shape, the plan's last.
    static let current = RoutineSchemaV13.self
}
