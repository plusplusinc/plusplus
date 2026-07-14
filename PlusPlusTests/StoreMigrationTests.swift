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

    /// V1 → V2: the custom stage adds `uuid` and its `didMigrate` backfills
    /// a FRESH, UNIQUE value per row (a lightweight column-add would give
    /// every migrated row the same default). Relationships survive.
    @Test func migratesV1ToV2AssigningUniqueUUIDs() throws {
        let url = tempURL()
        try writeV1ProbeData(to: url)

        let v2 = AppSchema.latest
        let config = ModelConfiguration(schema: v2, url: url, allowsSave: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: v2, migrationPlan: AppMigrationPlan.self, configurations: [config])
        let ctx = ModelContext(container)

        let routines = try ctx.fetch(FetchDescriptor<Routine>())
        let groups = try ctx.fetch(FetchDescriptor<ExerciseGroup>())
        let entries = try ctx.fetch(FetchDescriptor<RoutineExercise>())
        #expect(routines.count == 1)
        #expect(groups.count == 1)
        #expect(entries.count == 1)

        // Every routine-family row has a distinct uuid after backfill.
        let ids = routines.map(\.uuid) + groups.map(\.uuid) + entries.map(\.uuid)
        let distinct = Set(ids).count == ids.count
        #expect(distinct)
        #expect(ids.count == 3)

        // Relationships survived the version bump.
        #expect(routines.first?.sortedGroups.first?.sortedExercises.first?.exercise?.name == "Probe Press")
    }

    /// Seed a routine + group + exercise into a V1 (pre-`uuid`) store using
    /// the frozen snapshot classes, releasing the container before return.
    private func writeV1ProbeData(to url: URL) throws {
        let v1 = Schema(versionedSchema: AppSchemaV1.self)
        let config = ModelConfiguration(schema: v1, url: url, allowsSave: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: v1, configurations: [config])
        let ctx = ModelContext(container)

        let ex = Exercise(name: "Probe Press", muscleGroup: .chest)
        ctx.insert(ex)
        let routine = AppSchemaV1.Routine(name: "Probe Routine")
        ctx.insert(routine)
        let group = AppSchemaV1.ExerciseGroup(order: 0, sets: 3)
        ctx.insert(group)
        group.routine = routine
        let entry = AppSchemaV1.RoutineExercise(exercise: ex, order: 0)
        ctx.insert(entry)
        entry.group = group

        try ctx.save()
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
