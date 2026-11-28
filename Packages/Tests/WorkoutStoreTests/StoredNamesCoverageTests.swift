import SwiftData
import Testing
@testable import WorkoutStore

/// `StoredNamesTests` pins each version by hand and stays untouched by code renames, so it can't
/// read the plan's list itself. This holds the two together: a version added to the plan fails
/// here until it is pinned there too.
@Suite("Stored names coverage")
struct StoredNamesCoverageTests {
    @Test("Every schema version the migration plan opens is one the stored-names pin covers")
    func planMatchesPin() {
        let opened = StoreMigrationPlan.schemas.map { $0.versionIdentifier }
        #expect(
            opened == (1 ... 16).map { Schema.Version($0, 0, 0) },
            "Pin the new version's names in StoredNamesTests, then add it here",
        )
    }
}
