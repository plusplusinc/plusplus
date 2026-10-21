import SwiftData

/// Every stored shape the app has shipped, oldest first, and a lightweight stage between each,
/// since every change so far only added an attribute or a model.
enum RoutineMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            RoutineSchemaV1.self,
            RoutineSchemaV2.self,
            RoutineSchemaV3.self,
            RoutineSchemaV4.self,
            RoutineSchemaV5.self,
        ]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: RoutineSchemaV1.self, toVersion: RoutineSchemaV2.self),
            .lightweight(fromVersion: RoutineSchemaV2.self, toVersion: RoutineSchemaV3.self),
            .lightweight(fromVersion: RoutineSchemaV3.self, toVersion: RoutineSchemaV4.self),
            .lightweight(fromVersion: RoutineSchemaV4.self, toVersion: RoutineSchemaV5.self),
        ]
    }

    /// The current shape, the plan's last.
    static let current = RoutineSchemaV5.self
}
