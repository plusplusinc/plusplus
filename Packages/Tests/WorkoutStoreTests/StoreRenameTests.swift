import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

/// The store written by a shipped build, opened under today's plan.
@Suite("Store rename")
struct StoreRenameTests {
    static func openCurrent(at url: URL) throws -> ModelContainer {
        try ModelContainer(
            for: Store.schema,
            migrationPlan: StoreMigrationPlan.self,
            configurations: ModelConfiguration(schema: Store.schema, url: url),
        )
    }

    @Test("A V14 store written by a shipped build opens with every row, field, and link it held")
    func committedStoreKept() throws {
        let (url, before) = try StoreRenameFixture.copyCommitted()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(StoreRenameFixture.counts(before) == [
            "workout": 3, "row": 6, "session": 3, "set": 8, "exercise": 2, "customization": 1,
        ])
        let container = try Self.openCurrent(at: url)
        #expect(try StoreRenameFixture.lines(old: ModelContext(container)) == before)
    }
}
