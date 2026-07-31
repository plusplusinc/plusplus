import Foundation
import Testing
@testable import PlusPlus

/// Quick-start picks are name-keyed device state, so a catalog rename
/// has to carry them along — the indoor-bike merge renames a row
/// precisely because renames keep the object, and a pick should keep
/// it too.
@Suite("Quick-start picks")
struct QuickStartPicksTests {
    /// A throwaway domain per test: `rename` takes the defaults it
    /// writes, so nothing here touches the standard suite.
    private func makeDefaults() throws -> UserDefaults {
        let name = "quickstart-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("A rename follows the row")
    func renameFollows() throws {
        let defaults = try makeDefaults()
        defaults.set(QuickStartPicks.raw(from: ["Running", "Stationary Bike"]), forKey: QuickStartPicks.key)

        QuickStartPicks.rename(from: "Stationary Bike", to: "Indoor Cycling", defaults: defaults)

        let stored = try #require(defaults.string(forKey: QuickStartPicks.key))
        #expect(QuickStartPicks.names(from: stored) == ["Running", "Indoor Cycling"])
    }

    @Test("Renaming onto a name already picked deduplicates instead of doubling")
    func renameDeduplicates() throws {
        let defaults = try makeDefaults()
        defaults.set(QuickStartPicks.raw(from: ["Indoor Cycling", "Stationary Bike"]), forKey: QuickStartPicks.key)

        QuickStartPicks.rename(from: "Stationary Bike", to: "Indoor Cycling", defaults: defaults)

        let stored = try #require(defaults.string(forKey: QuickStartPicks.key))
        #expect(QuickStartPicks.names(from: stored) == ["Indoor Cycling"])
    }

    @Test("No stored picks, or a name never picked, writes nothing")
    func noOpPaths() throws {
        let defaults = try makeDefaults()
        // Nothing stored: rename must not conjure a list.
        QuickStartPicks.rename(from: "A", to: "B", defaults: defaults)
        #expect(defaults.string(forKey: QuickStartPicks.key) == nil)

        // Stored, but the old name isn't in it: untouched.
        defaults.set(QuickStartPicks.raw(from: ["Running"]), forKey: QuickStartPicks.key)
        QuickStartPicks.rename(from: "Rowing", to: "Erg", defaults: defaults)
        let stored = try #require(defaults.string(forKey: QuickStartPicks.key))
        #expect(QuickStartPicks.names(from: stored) == ["Running"])
    }
}
