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

    /// A store created with a PLAIN `Schema([...])` and NO migration plan
    /// (how the app opened pre-#155) reopens cleanly under the versioned
    /// schema + plan, data intact — the load-bearing assumption that
    /// attaching a migration plan doesn't reset an existing plan-less store
    /// of the same shape. (The pre-`uuid` → `uuid` transition specifically
    /// is covered by `migratesV1ToV2AssigningUniqueUUIDs`.)
    @Test func plainSchemaStoreOpensUnderVersionedSchemaWithoutLoss() throws {
        let url = tempURL()

        // Write with the OLD plain schema, then release the container so
        // its SQLite handle is closed before we reopen the same file.
        // ⚠️ Caveat: SwiftData/CoreData caches store state per-URL within a
        // process, so this reopen may reuse the writer's coordinator rather
        // than proving a true cold open — the definitive proof is the
        // on-device upgrade-over-real-data pass, not this test.
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

    /// The launch backfill ENFORCES UNIQUENESS — it repairs both a clean
    /// migration (all uuids nil) AND a store already stamped with the shared
    /// property-default constant (all uuids equal, the real on-device bug
    /// where every routine opened the same one and the rail drew duplicate
    /// rows). This is the production populate path (`PlusPlusApp` runs it at
    /// launch), so it's the meaningful thing to lock.
    @Test func backfillEnforcesUniqueUUIDs() throws {
        let url = tempURL()
        let schema = AppSchema.latest
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: [config])
        let ctx = ModelContext(container)

        let ex = Exercise(name: "Probe Press", muscleGroup: .chest)
        ctx.insert(ex)
        // Three routines, each with a group + exercise.
        for i in 0..<3 {
            let routine = Routine(name: "Probe Routine \(i)")
            ctx.insert(routine)
            routine.addExerciseInNewGroup(ex, context: ctx)
        }

        // Simulate the migration bug: every row gets the SAME uuid (the
        // shared property-default constant), plus one nil for good measure.
        let shared = UUID()
        for (i, routine) in try ctx.fetch(FetchDescriptor<Routine>()).enumerated() {
            routine.uuid = i == 0 ? nil : shared
        }
        for group in try ctx.fetch(FetchDescriptor<ExerciseGroup>()) { group.uuid = shared }
        for entry in try ctx.fetch(FetchDescriptor<RoutineExercise>()) { entry.uuid = shared }
        try ctx.save()

        SeedData.backfillModelUUIDsIfNeeded(context: ctx)

        let routines = try ctx.fetch(FetchDescriptor<Routine>())
        let groups = try ctx.fetch(FetchDescriptor<ExerciseGroup>())
        let entries = try ctx.fetch(FetchDescriptor<RoutineExercise>())
        let ids = routines.compactMap(\.uuid) + groups.compactMap(\.uuid) + entries.compactMap(\.uuid)
        #expect(ids.count == 9)          // 3 routines + 3 groups + 3 entries, none nil
        #expect(Set(ids).count == 9)     // ALL distinct — no shared uuid survives
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
