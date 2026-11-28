import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

/// `StoreRenameBackup`: the copy kept beside a store while it is renamed, each row of its
/// table, and each way the rename can fail, on the committed V14 store.
@Suite("Store rename backup")
struct StoreRenameBackupTests {
    /// The committed store's numbers, as counted under either names.
    static let fixtureCounts = StoreRenameBackup.Counts(
        workouts: 3,
        rows: 6,
        rowsInWorkouts: 6,
        sessions: 3,
        sets: 8,
        setsInSessions: 8,
        createdExercises: 2,
        customizations: 1,
    )

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    static func currentLines(at url: URL) throws -> [String] {
        try StoreRenameFixture.lines(current: ModelContext(StoreRenameTests.openCurrent(at: url)))
    }

    @Test("A store under old names is copied aside to rename, the copy removed once counts match")
    func copiedThenRemoved() throws {
        let (url, before) = try StoreRenameFixture.copyCommitted()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        // The plan throws if the copy isn't whole while it runs.
        let container = try StoreRenameBackup.open(at: url, plan: SeesTheCopy.self)
        #expect(!Self.exists(StoreRenameBackup.folder(for: url)))
        #expect(try StoreRenameFixture.lines(current: ModelContext(container)) == before)
    }

    @Test(
        "A migration that loses a row is refused, and the original store is back at the next open",
    )
    func lostRowRefused() throws {
        let (url, before) = try StoreRenameFixture.copyCommitted()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let refused = try #require(throws: StoreRenameBackup.CountsDiffer.self) {
            try StoreRenameBackup.open(at: url, plan: LosesASet.self)
        }
        #expect(refused.before == Self.fixtureCounts)
        #expect(refused.after.sets == 7)
        let backup = StoreRenameBackup.folder(for: url)
        #expect(Self.exists(backup.appending(path: "counts.json")))

        let container = try StoreRenameBackup.open(at: url)
        #expect(try StoreRenameFixture.lines(current: ModelContext(container)) == before)
        #expect(!Self.exists(backup))
    }

    @Test("A migration that leaves a session as a workout is refused")
    func sessionLeftRefused() throws {
        let (url, _) = try StoreRenameFixture.copyCommitted()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let refused = try #require(throws: StoreRenameBackup.CountsDiffer.self) {
            try StoreRenameBackup.open(at: url, plan: LeavesASession.self)
        }
        #expect(refused.after.workouts == refused.before.workouts + 1)
        #expect(Self.exists(StoreRenameBackup.folder(for: url).appending(path: "counts.json")))
    }

    @Test("A copy cut short while it was made is thrown away and made again")
    func partialCopyRetaken() throws {
        let (url, before) = try StoreRenameFixture.copyCommitted()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let backup = StoreRenameBackup.folder(for: url)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: false)
        try Data("cut short".utf8).write(to: backup.appending(path: "PlusPlus.store"))

        let container = try StoreRenameBackup.open(at: url)
        #expect(try StoreRenameFixture.lines(current: ModelContext(container)) == before)
        #expect(!Self.exists(backup))
    }

    enum Damage: CaseIterable {
        case missing
        case truncated
    }

    @Test(
        "A whole copy beside a missing or half-written store puts the store back",
        arguments: Damage.allCases,
    )
    func wholeCopyRestored(_ damage: Damage) throws {
        let (url, before) = try StoreRenameFixture.copyCommitted()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let backup = StoreRenameBackup.folder(for: url)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: false)
        try FileManager.default.copyItem(at: url, to: backup.appending(path: "PlusPlus.store"))
        try JSONEncoder().encode(Self.fixtureCounts)
            .write(to: backup.appending(path: "counts.json"))
        switch damage {
        case .missing:
            try FileManager.default.removeItem(at: url)
        case .truncated:
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: 4096)
            try handle.close()
        }

        let container = try StoreRenameBackup.open(at: url)
        #expect(try StoreRenameFixture.lines(current: ModelContext(container)) == before)
        #expect(!Self.exists(backup))
    }

    @Test("A copy whose removal was cut short is tidied at the next open")
    func partialRemovalTidied() throws {
        let (url, before) = try StoreRenameFixture.copyCommitted()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        _ = try StoreRenameBackup.open(at: url)
        let backup = StoreRenameBackup.folder(for: url)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: false)
        try Data("left".utf8).write(to: backup.appending(path: "PlusPlus.store"))

        let container = try StoreRenameBackup.open(at: url)
        #expect(!Self.exists(backup))
        #expect(try StoreRenameFixture.lines(current: ModelContext(container)) == before)
    }

    @Test("A new install makes no copy")
    func newInstall() throws {
        let folder = try StoreRenameFixture.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "PlusPlus.store")
        _ = try StoreRenameBackup.open(at: url)
        #expect(Self.exists(url))
        #expect(!Self.exists(StoreRenameBackup.folder(for: url)))
    }

    @Test("A store already renamed opens as it is, read as holding no old names")
    func alreadyRenamed() throws {
        let (url, before) = try StoreRenameFixture.copyCommitted()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(try StoreRenameBackup.holdsOldNames(url))
        _ = try StoreRenameBackup.open(at: url)
        #expect(try !StoreRenameBackup.holdsOldNames(url))
        let container = try StoreRenameBackup.open(at: url)
        #expect(!Self.exists(StoreRenameBackup.folder(for: url)))
        #expect(try StoreRenameFixture.lines(current: ModelContext(container)) == before)
    }

    @Test("When the copy can't be made, the store is left as it was and nothing is migrated")
    func noCopyNoMigration() throws {
        let (url, _) = try StoreRenameFixture.copyCommitted()
        let backup = StoreRenameBackup.folder(for: url)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: false)
        try Data("kept".utf8).write(to: backup.appending(path: "file"))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555],
            ofItemAtPath: backup.path(percentEncoded: false),
        )
        defer {
            try? FileManager.default
                .setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: backup.path(percentEncoded: false),
                )
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }

        #expect(throws: (any Error).self) { try StoreRenameBackup.open(at: url) }
        #expect(try StoreRenameBackup.holdsOldNames(url))
    }
}
