import CoreData
import Foundation
import OSLog
import SwiftData

/// Opens a store on disk through the one migration that moves rows, V14's names to V17's,
/// keeping a copy of the store until the result is checked. Staged migration rewrites the file
/// in place, with no way back, so the copy is the way back.
///
/// The copy is a folder beside the store, `<name>-before-rename`, holding the store's files and
/// `counts.json`, the eight numbers counted under the old names. `counts.json` is written last,
/// so its presence is what makes the copy whole. At each open:
///
/// - A whole copy: the store's files are put back from it, then migrated, checked, and the
///   copy removed. The app is never handed a store while a whole copy exists, so the copy
///   holds everything; starting again from it makes a run cut short at any moment, however
///   SQLite and SwiftData left the file, the same case.
/// - No whole copy, and a store under the old names (its metadata lists `StoredRoutine`): any
///   part of a copy is deleted, the store copied, counted under a plan that ends at V14, and
///   `counts.json` written; then migrated, checked, and the copy removed.
/// - Neither, a new install or a store already renamed: any part of a copy is deleted, and the
///   store opens as it would without this.
///
/// Checked means counted again under the new names, before the store is returned, and equal.
/// When it isn't, or the migration throws, the copy stays and the open throws, so the next
/// launch starts again from it. A copy that can't be made throws before anything migrates.
enum StoreRenameBackup {
    /// What a store holds, counted under either names, so a row dropped or left behind differs.
    struct Counts: Codable, Equatable, CustomStringConvertible {
        var workouts = 0
        var rows = 0
        var rowsInWorkouts = 0
        var sessions = 0
        var sets = 0
        var setsInSessions = 0
        var createdExercises = 0
        var customizations = 0

        var description: String {
            "workouts \(workouts), rows \(rows) (\(rowsInWorkouts) in one), sessions \(sessions), "
                + "sets \(sets) (\(setsInSessions) in one), exercises \(createdExercises), "
                + "customizations \(customizations)"
        }
    }

    /// The migration's counts didn't match: the copy is kept for the next open.
    struct CountsDiffer: Error {
        var before: Counts
        var after: Counts
    }

    /// The store in the file at `url`, migrated under `plan`, which a test replaces.
    static func open(
        at url: URL,
        schema: Schema = Store.schema,
        plan: any SchemaMigrationPlan.Type = StoreMigrationPlan.self,
    ) throws -> ModelContainer {
        let backup = folder(for: url)
        let countsURL = backup.appending(path: "counts.json")
        let files = FileManager.default
        let before: Counts?
        if let saved = try? Data(contentsOf: countsURL) {
            before = try JSONDecoder().decode(Counts.self, from: saved)
            try restore(url, from: backup)
            Logger.storage.notice("Put the store back from its copy before the rename")
        } else {
            if files.fileExists(atPath: backup.path(percentEncoded: false)) {
                try files.removeItem(at: backup)
            }
            if try holdsOldNames(url) {
                try copy(url, to: backup)
                let counts = try countOld(at: url)
                try JSONEncoder().encode(counts).write(to: countsURL, options: .atomic)
                before = counts
            } else {
                before = nil
            }
        }
        let container: ModelContainer
        do {
            container = try WorkoutStoreContainer.make(at: url, schema: schema, migrationPlan: plan)
        } catch {
            if let before {
                Logger.storage
                    .fault("The rename failed, copy kept; before: \(before, privacy: .public)")
            }
            throw error
        }
        guard let before else { return container }
        let after = try countNew(in: ModelContext(container))
        guard after == before else {
            Logger.storage.fault("""
            The rename's counts differ, copy kept; before: \(before, privacy: .public); \
            after: \(after, privacy: .public)
            """)
            throw CountsDiffer(before: before, after: after)
        }
        try files.removeItem(at: countsURL)
        try files.removeItem(at: backup)
        Logger.storage.notice("""
        Renamed the store; before: \(before, privacy: .public); \
        after: \(after, privacy: .public); backup removed
        """)
        return container
    }

    /// The copy's folder, beside the store.
    static func folder(for url: URL) -> URL {
        url.deletingLastPathComponent()
            .appending(path: "\(url.deletingPathExtension().lastPathComponent)-before-rename")
    }

    /// Whether the file at `url` is a store under the names before V15; false when there is
    /// none. Read from its metadata, without opening it, which would migrate it.
    static func holdsOldNames(_ url: URL) throws -> Bool {
        // Not `path()`, which escapes the space in `Application Support` and finds no file.
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return false
        }
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            type: .sqlite,
            at: url,
        )
        let hashes = metadata[NSStoreModelVersionHashesKey] as? [String: Any] ?? [:]
        return hashes["StoredRoutine"] != nil
    }

    /// The store's files: the store and SQLite's own beside it, its write-ahead log and index.
    private static func storeFiles(of url: URL, in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
            .filter { $0.hasPrefix(url.lastPathComponent) }
    }

    private static func copy(_ url: URL, to backup: URL) throws {
        let files = FileManager.default
        try files.createDirectory(at: backup, withIntermediateDirectories: false)
        let folder = url.deletingLastPathComponent()
        for name in try storeFiles(of: url, in: folder) {
            try files.copyItem(at: folder.appending(path: name), to: backup.appending(path: name))
        }
    }

    private static func restore(_ url: URL, from backup: URL) throws {
        let files = FileManager.default
        let folder = url.deletingLastPathComponent()
        for name in try storeFiles(of: url, in: folder) {
            try files.removeItem(at: folder.appending(path: name))
        }
        for name in try storeFiles(of: url, in: backup) {
            try files.copyItem(at: backup.appending(path: name), to: folder.appending(path: name))
        }
    }

    /// The store at `url`, opened under the plan up to V14, as every update before the rename
    /// opened it, and counted under its names.
    private static func countOld(at url: URL) throws -> Counts {
        let container = try WorkoutStoreContainer.make(
            at: url,
            schema: Schema(versionedSchema: RoutineSchemaV14.self),
            migrationPlan: StoreMigrationPlanBeforeRename.self,
        )
        let context = ModelContext(container)
        return try Counts(
            workouts: context.fetchCount(FetchDescriptor<RoutineSchemaV7.StoredRoutine>()),
            rows: context.fetchCount(FetchDescriptor<RoutineSchemaV7.StoredRoutineExercise>()),
            rowsInWorkouts: context
                .fetchCount(FetchDescriptor<RoutineSchemaV7.StoredRoutineExercise>(
                    predicate: #Predicate { $0.routine != nil },
                )),
            sessions: context.fetchCount(FetchDescriptor<RoutineSchemaV14.StoredWorkout>()),
            sets: context.fetchCount(FetchDescriptor<RoutineSchemaV14.StoredSet>()),
            setsInSessions: context.fetchCount(FetchDescriptor<RoutineSchemaV14.StoredSet>(
                predicate: #Predicate { $0.workout != nil },
            )),
            createdExercises: context.fetchCount(FetchDescriptor<RoutineSchemaV8.StoredExercise>()),
            customizations: context
                .fetchCount(FetchDescriptor<RoutineSchemaV10.StoredCustomization>()),
        )
    }

    /// The same numbers under today's names.
    static func countNew(in context: ModelContext) throws -> Counts {
        try Counts(
            workouts: context.fetchCount(FetchDescriptor<StoredWorkout>()),
            rows: context.fetchCount(FetchDescriptor<StoredWorkoutExercise>()),
            rowsInWorkouts: context.fetchCount(FetchDescriptor<StoredWorkoutExercise>(
                predicate: #Predicate { $0.workout != nil },
            )),
            sessions: context.fetchCount(FetchDescriptor<StoredWorkoutSession>()),
            sets: context.fetchCount(FetchDescriptor<StoredLoggedSet>()),
            setsInSessions: context.fetchCount(FetchDescriptor<StoredLoggedSet>(
                predicate: #Predicate { $0.workoutSession != nil },
            )),
            createdExercises: context.fetchCount(FetchDescriptor<StoredExercise>()),
            customizations: context.fetchCount(FetchDescriptor<StoredCustomization>()),
        )
    }
}

/// `StoreMigrationPlan` up to V14, the last shape before the rename: what a store is counted
/// under before it is renamed.
enum StoreMigrationPlanBeforeRename: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        StoreMigrationPlan.schemas.filter { $0.versionIdentifier.major <= 14 }
    }

    static var stages: [MigrationStage] {
        Array(StoreMigrationPlan.stages.prefix(schemas.count - 1))
    }
}
