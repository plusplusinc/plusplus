import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Types shared between the app and the widget extension (#147). This
/// file compiles into BOTH targets — keep it dependency-light.

/// The App Group both targets read/write. Widgets can't see the app's
/// SwiftData store; the app publishes a small snapshot instead.
public enum PlusPlusAppGroup {
    public static let identifier = "group.com.davidcole.plusplus"
    static let snapshotKey = "widgetSnapshot"
}

#if canImport(ActivityKit)
/// The rest countdown as a Live Activity (Dynamic Island + Lock
/// Screen). Date-based like the in-app timer, so suspension can't
/// drift it; the island renders the countdown natively from endDate.
struct RestActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// When rest ends; the island's timer text counts down to it.
        var endDate: Date
        /// What's up next when rest is over.
        var exerciseName: String
        var setNumber: Int
    }

    /// Fixed for the activity's life: the routine being performed.
    var routineName: String
}
#endif

/// What the widgets know: due-ness, the routine list (for intents), and
/// streak numbers. Written by the app on launch/backgrounding and after
/// data changes; read by timeline providers. Deliberately tiny.
struct WidgetSnapshot: Codable {
    struct DueRoutine: Codable {
        var name: String
        var caption: String
        var exerciseCount: Int
    }

    var generatedAt: Date
    var routineNames: [String]
    var due: [DueRoutine]
    /// Consecutive weeks (ending this week) with at least one finished
    /// workout.
    var streakWeeks: Int
    /// Finished-workout counts for the last 12 weeks, oldest first —
    /// the widget's mini contribution row.
    var weeklyCounts: [Int]

    // MARK: - App Group persistence

    static func load() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: PlusPlusAppGroup.identifier),
              let data = defaults.data(forKey: PlusPlusAppGroup.snapshotKey)
        else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let defaults = UserDefaults(suiteName: PlusPlusAppGroup.identifier),
              let data = try? JSONEncoder().encode(self)
        else { return }
        defaults.set(data, forKey: PlusPlusAppGroup.snapshotKey)
    }
}
