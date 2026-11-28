import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

/// A rename cut short, by an error or by the process being killed, and a move run again: each
/// leaves a store the next open renames whole, from the copy.
@Suite("Store rename cut short")
struct StoreRenameStopTests {
    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    @Test(
        "A migration stopped before the sessions move keeps the copy; the next open renames all",
    )
    func stoppedBeforeSessions() throws {
        let (url, before) = try StoreRenameFixture.copyCommitted()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        // SwiftData throws its own error for a stage's.
        #expect(throws: (any Error).self) {
            try StoreRenameBackup.open(at: url, plan: StopsBeforeSessions.self)
        }
        let backup = StoreRenameBackup.folder(for: url)
        #expect(Self.exists(backup.appending(path: "counts.json")))

        let container = try StoreRenameBackup.open(at: url)
        #expect(try StoreRenameFixture.lines(current: ModelContext(container)) == before)
        #expect(!Self.exists(backup))
    }

    @Test(
        "A migration stopped after the workouts move, mid-stage, starts again from the copy",
    )
    func stoppedAfterWorkouts() throws {
        let (url, before) = try StoreRenameFixture.copyCommitted()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(throws: (any Error).self) {
            try StoreRenameBackup.open(at: url, plan: StopsAfterWorkouts.self)
        }
        let backup = StoreRenameBackup.folder(for: url)
        #expect(Self.exists(backup.appending(path: "counts.json")))

        let container = try StoreRenameBackup.open(at: url)
        #expect(try StoreRenameFixture.lines(current: ModelContext(container)) == before)
        #expect(!Self.exists(backup))
    }

    @Test("Each move run twice moves nothing the second time")
    func movesTwice() throws {
        let (sessionsURL, _) = try StoreRenameFixture.copyCommitted()
        let (workoutsURL, _) = try StoreRenameFixture.copyCommitted()
        defer {
            try? FileManager.default.removeItem(at: sessionsURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: workoutsURL.deletingLastPathComponent())
        }
        let v15 = Schema(versionedSchema: StoreSchemaV15.self)
        let sessions = try ModelContext(ModelContainer(
            for: v15,
            migrationPlan: PlanToV15.self,
            configurations: ModelConfiguration(schema: v15, url: sessionsURL),
        ))
        func movedSessions() throws -> [Int] {
            try [
                sessions.fetchCount(FetchDescriptor<StoredWorkoutSession>()),
                sessions.fetchCount(FetchDescriptor<StoredLoggedSet>()),
            ]
        }
        try StoreMigrationPlan.moveSessions(in: sessions)
        #expect(try movedSessions() == [3, 8])
        try StoreMigrationPlan.moveSessions(in: sessions)
        #expect(try movedSessions() == [3, 8])

        let v16 = Schema(versionedSchema: StoreSchemaV16.self)
        let workouts = try ModelContext(ModelContainer(
            for: v16,
            migrationPlan: PlanToV16.self,
            configurations: ModelConfiguration(schema: v16, url: workoutsURL),
        ))
        func movedWorkouts() throws -> [Int] {
            try [
                workouts.fetchCount(FetchDescriptor<StoredWorkout>()),
                workouts.fetchCount(FetchDescriptor<StoredWorkoutExercise>()),
            ]
        }
        try StoreMigrationPlan.moveWorkouts(in: workouts)
        #expect(try movedWorkouts() == [3, 6])
        try StoreMigrationPlan.moveWorkouts(in: workouts)
        #expect(try movedWorkouts() == [3, 6])
    }

    #if os(macOS)
    /// Exit tests run on macOS only, so Xcode Cloud, which runs the package on the simulator,
    /// skips this; `scripts/test.sh` runs it. The thrown-error tests above run on both.
    @Test("A process killed after the sessions move leaves a store the next launch renames whole")
    func killedAfterSessions() async throws {
        let (url, before) = try StoreRenameFixture.copyCommitted()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        await #expect(processExitsWith: .signal(SIGKILL)) { [url = url as URL] in
            _ = try? StoreRenameBackup.open(at: url, plan: KilledAfterSessions.self)
        }
        try Self.renamedWhole(at: url, before: before)
    }

    @Test("A process killed after the workouts move leaves a store the next launch renames whole")
    func killedAfterWorkouts() async throws {
        let (url, before) = try StoreRenameFixture.copyCommitted()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        await #expect(processExitsWith: .signal(SIGKILL)) { [url = url as URL] in
            _ = try? StoreRenameBackup.open(at: url, plan: KilledAfterWorkouts.self)
        }
        try Self.renamedWhole(at: url, before: before)
    }

    /// The copy is whole after the kill, and the next open renames the store from it.
    private static func renamedWhole(at url: URL, before: [String]) throws {
        #expect(exists(StoreRenameBackup.folder(for: url).appending(path: "counts.json")))
        let container = try StoreRenameBackup.open(at: url)
        #expect(try StoreRenameFixture.lines(current: ModelContext(container)) == before)
        #expect(!exists(StoreRenameBackup.folder(for: url)))
    }
    #endif
}

#if os(macOS)
/// Moves the sessions, saved, then kills the process: no unwinding, the file left as it lies.
enum KilledAfterSessions: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        StoreMigrationPlan.schemas
    }

    static var stages: [MigrationStage] {
        StoreRenamePlans.stages(sessions: { context in
            try StoreMigrationPlan.moveSessions(in: context)
            kill(getpid(), SIGKILL)
        })
    }
}

/// Moves the workouts, saved, then kills the process.
enum KilledAfterWorkouts: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        StoreMigrationPlan.schemas
    }

    static var stages: [MigrationStage] {
        StoreRenamePlans.stages(workouts: { context in
            try StoreMigrationPlan.moveWorkouts(in: context)
            kill(getpid(), SIGKILL)
        })
    }
}
#endif
