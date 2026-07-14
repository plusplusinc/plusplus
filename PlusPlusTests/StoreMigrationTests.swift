import Foundation
import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

/// #155: the store-migration policy. These lock the core assumptions of
/// adopting a `VersionedSchema` + `SchemaMigrationPlan` on a store that
/// shipped WITHOUT one.
///
/// ⚠️ Simulator/CI success is necessary but NOT sufficient — the Axiom
/// migration guidance is emphatic that a real upgrade-over-existing-data
/// pass on a device is the only proof. These guard the wiring and the
/// no-data-loss contract at the level a headless test can.
@Suite("StoreMigration")
struct StoreMigrationTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-\(UUID().uuidString).store")
    }

    /// A store created with the pre-#155 PLAIN schema (the exact shape the
    /// app shipped with) reopens cleanly under the versioned schema V1 +
    /// migration plan, data intact. This is the load-bearing assumption:
    /// adopting `VersionedSchema` V1 == the current entities must NOT reset
    /// existing unversioned stores.
    @Test func unversionedStoreOpensUnderVersionedSchemaV1WithoutLoss() throws {
        let url = tempURL()

        // Write with the OLD plain schema, then release the container so
        // its SQLite handle is closed before we reopen the same file.
        try writeProbeData(to: url)

        let versioned = AppSchema.latest
        let readConfig = ModelConfiguration(schema: versioned, url: url, allowsSave: true, cloudKitDatabase: .none)
        let readContainer = try ModelContainer(for: versioned, migrationPlan: AppMigrationPlan.self, configurations: [readConfig])
        let ctx = ModelContext(readContainer)

        let routines = try ctx.fetch(FetchDescriptor<Routine>())
        #expect(routines.count == 1)
        let routine = try #require(routines.first)
        #expect(routine.name == "Probe Routine")
        // Relationships survived the reopen.
        #expect(routine.sortedGroups.first?.sortedExercises.first?.exercise?.name == "Probe Press")
        #expect(try ctx.fetch(FetchDescriptor<Exercise>()).count == 1)
        #expect(try ctx.fetch(FetchDescriptor<WorkoutSession>()).count == 1)
    }

    /// A fresh store created directly at the latest versioned schema round-
    /// trips through the plan (the fresh-install path, no migration).
    @Test func freshVersionedStoreRoundTrips() throws {
        let url = tempURL()
        let schema = AppSchema.latest
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: [config])
        let ctx = ModelContext(container)

        let ex = Exercise(name: "Probe Press", muscleGroup: .chest)
        ctx.insert(ex)
        let routine = Routine(name: "Probe Routine")
        ctx.insert(routine)
        routine.addExerciseInNewGroup(ex, context: ctx)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<Routine>()).count == 1)
    }

    /// Seed a routine + exercise + finished session with the pre-#155 plain
    /// schema, in a scope that releases the container before returning so
    /// the file is closed for the reopen under test.
    private func writeProbeData(to url: URL) throws {
        let plain = Schema([
            Routine.self, Exercise.self, Equipment.self, EquipmentLibrary.self,
            WorkoutSession.self, SetLog.self,
        ])
        let config = ModelConfiguration(schema: plain, url: url, allowsSave: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: plain, configurations: [config])
        let ctx = ModelContext(container)

        let ex = Exercise(name: "Probe Press", muscleGroup: .chest)
        ctx.insert(ex)
        let routine = Routine(name: "Probe Routine")
        ctx.insert(routine)
        routine.addExerciseInNewGroup(ex, context: ctx)

        let session = WorkoutSession(routine: routine, routineName: routine.name)
        session.endedAt = Date()
        ctx.insert(session)

        try ctx.save()
    }
}
