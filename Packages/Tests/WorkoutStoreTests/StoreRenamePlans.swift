import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

/// The app's migration plan with its two moves, or its last stage's end, replaced, so a test
/// can stop a migration, lose a row from it, or look at the copy while it runs.
enum StoreRenamePlans {
    typealias Step = (ModelContext) throws -> Void

    struct Stopped: Error { }

    /// The plan's stages up to V15, then the two moves as given.
    static func stages(
        sessions: @escaping Step = StoreMigrationPlan.moveSessions(in:),
        workouts: @escaping Step = StoreMigrationPlan.moveWorkouts(in:),
        afterLast: Step? = nil,
    ) -> [MigrationStage] {
        Array(StoreMigrationPlan.stages.dropLast(2)) + [
            .custom(
                fromVersion: StoreSchemaV15.self,
                toVersion: StoreSchemaV16.self,
                willMigrate: sessions,
                didMigrate: nil,
            ),
            .custom(
                fromVersion: StoreSchemaV16.self,
                toVersion: StoreSchemaV17.self,
                willMigrate: workouts,
                didMigrate: afterLast,
            ),
        ]
    }

    /// The plan's versions up to `last`, and the stages between them, as the app's.
    static func schemas(through last: Int) -> [any VersionedSchema.Type] {
        StoreMigrationPlan.schemas.filter { $0.versionIdentifier.major <= last }
    }

    /// The store's file, from a stage's context.
    static func url(of context: ModelContext) throws -> URL {
        try #require(context.container.configurations.first?.url)
    }
}

/// Stops before the sessions move.
enum StopsBeforeSessions: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        StoreMigrationPlan.schemas
    }

    static var stages: [MigrationStage] {
        StoreRenamePlans.stages(sessions: { _ in throw StoreRenamePlans.Stopped() })
    }
}

/// Moves the workouts, then stops before its stage ends.
enum StopsAfterWorkouts: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        StoreMigrationPlan.schemas
    }

    static var stages: [MigrationStage] {
        StoreRenamePlans.stages(workouts: { context in
            try StoreMigrationPlan.moveWorkouts(in: context)
            throw StoreRenamePlans.Stopped()
        })
    }
}

/// Loses one logged set after the last stage.
enum LosesASet: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        StoreMigrationPlan.schemas
    }

    static var stages: [MigrationStage] {
        StoreRenamePlans.stages(afterLast: { context in
            if let set = try context.fetch(FetchDescriptor<StoredLoggedSet>()).first {
                context.delete(set)
                try context.save()
            }
        })
    }
}

/// Leaves a session behind under its old name, which the next stage makes a workout.
enum LeavesASession: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        StoreMigrationPlan.schemas
    }

    static var stages: [MigrationStage] {
        StoreRenamePlans.stages(sessions: { context in
            try StoreMigrationPlan.moveSessions(in: context)
            context.insert(RoutineSchemaV14.StoredWorkout(id: UUID()))
            try context.save()
        })
    }
}

/// The app's plan, checking while it runs that the copy beside the store is whole.
enum SeesTheCopy: SchemaMigrationPlan {
    struct NoCopy: Error { }

    static var schemas: [any VersionedSchema.Type] {
        StoreMigrationPlan.schemas
    }

    static var stages: [MigrationStage] {
        StoreRenamePlans.stages(sessions: { context in
            let backup = try StoreRenameBackup.folder(for: StoreRenamePlans.url(of: context))
            let names = try FileManager.default.contentsOfDirectory(atPath: backup.path())
            guard names.contains("counts.json"), names.contains("PlusPlus.store") else {
                throw NoCopy()
            }
            try StoreMigrationPlan.moveSessions(in: context)
        })
    }
}

/// The app's plan up to V15, so a test can run the sessions move on a V15 store itself.
enum PlanToV15: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        StoreRenamePlans.schemas(through: 15)
    }

    static var stages: [MigrationStage] {
        Array(StoreMigrationPlan.stages.prefix(schemas.count - 1))
    }
}

/// The app's plan up to V16, so a test can run the workouts move on a V16 store itself.
enum PlanToV16: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        StoreRenamePlans.schemas(through: 16)
    }

    static var stages: [MigrationStage] {
        Array(StoreMigrationPlan.stages.prefix(schemas.count - 1))
    }
}
