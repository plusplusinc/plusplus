import Foundation
import PlusPlusKit
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Types shared between the app and the widget extension (#147). This
/// file compiles into BOTH targets — keep it dependency-light (the only
/// import beyond Foundation is PlusPlusKit, which is platform-pure and
/// linked by both).

/// The App Group both targets read/write. Widgets can't see the app's
/// SwiftData store; the app publishes a small snapshot instead.
public enum PlusPlusAppGroup {
    public static let identifier = "group.com.davidcole.plusplus"
    static let snapshotKey = "widgetSnapshot"
}

#if canImport(ActivityKit)
/// The active workout as a Live Activity (Dynamic Island + Lock Screen).
/// ONE activity spans the whole session (#322): it rides in `.working`
/// showing the current exercise, set progress, and count-up elapsed, and
/// swaps to `.resting` with a live countdown + controls between sets.
/// Date-based throughout (elapsed from `sessionStart`, countdown to
/// `restEnd`), so app suspension can't drift either timer — the island
/// renders both natively without the app being awake.
struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            /// Mid-set: elapsed + progress, no countdown.
            case working
            /// Between sets: countdown to `restEnd` + rest controls.
            case resting
        }

        var phase: Phase
        /// The CURRENT exercise while working; the UP-NEXT exercise while
        /// resting (the set you're about to do when the countdown ends).
        var exerciseName: String
        var setNumber: Int
        var setsCompleted: Int
        var totalSets: Int
        /// Session start, for the count-up elapsed timer.
        var sessionStart: Date
        /// When rest ends; the countdown drains to it. Nil while working.
        var restEnd: Date?
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

    /// A routine plus everything needed to compute its due-ness at ANY
    /// date (#159): the widget rolls the schedule forward locally, so a
    /// phone left in the gym bag for a week still shows the right day.
    struct ScheduledRoutine: Codable {
        var name: String
        var exerciseCount: Int
        /// Encoded `RoutineSchedule` (same JSON as `Routine.scheduleData`).
        var scheduleData: Data?
        var lastCompleted: Date?
        /// The completion before `lastCompleted` (#267): the Kit's
        /// banking rule needs it to tell an extra session from a
        /// make-up. Additive and optional — snapshots written before
        /// #267 decode nil, which just turns banking conservatively
        /// off until the app writes a fresh snapshot.
        var previousCompleted: Date? = nil
        /// The day the routine joined the library (`Routine.createdAt`),
        /// the schedule anchor (2026-07-14): the widget must compute
        /// due-ness with the SAME floor the app uses, or the two surfaces
        /// disagree on the early-banking edge. Additive/optional — old
        /// snapshots decode nil (no floor), matching pre-anchor behavior
        /// until the app writes a fresh one.
        var addedOn: Date? = nil

        var schedule: RoutineSchedule {
            guard let scheduleData,
                  let decoded = try? JSONDecoder().decode(RoutineSchedule.self, from: scheduleData)
            else { return .unscheduled }
            return decoded
        }
    }

    var generatedAt: Date
    var routineNames: [String]
    /// Due list frozen at write time — the fallback when `scheduled` is
    /// absent (a snapshot written before #159).
    var due: [DueRoutine]
    /// Consecutive weeks (ending this week) with at least one finished
    /// workout.
    var streakWeeks: Int
    /// Finished-workout counts for the last 12 weeks, oldest first —
    /// the widget's mini contribution row.
    var weeklyCounts: [Int]
    /// All schedulable routines with their schedules (#159). Optional so
    /// pre-#159 snapshots still decode.
    var scheduled: [ScheduledRoutine]?

    // MARK: - Freshness (#159): compute at a date instead of trusting
    // the frozen lists.

    /// What belongs on Today for `date`. Falls back to the frozen `due`
    /// list for old snapshots.
    func dueList(at date: Date, calendar: Calendar = .current) -> [DueRoutine] {
        guard let scheduled else { return due }
        return scheduled.compactMap { routine in
            let schedule = routine.schedule
            // `== .due` only: a carried `.missed` is not "due today" on the
            // widget either, matching the app's due cards (2026-07-14).
            guard case .due = schedule.dueState(
                lastCompleted: routine.lastCompleted,
                previousCompleted: routine.previousCompleted,
                today: date,
                addedOn: routine.addedOn,
                calendar: calendar
            ) else { return nil }
            return DueRoutine(
                name: routine.name,
                caption: schedule.shortLabel,
                exerciseCount: routine.exerciseCount
            )
        }
    }

    /// Streak + weekly buckets rolled forward to `date`: weeks that have
    /// passed since the snapshot was written become empty buckets, so a
    /// stale snapshot can't overstate the streak.
    func rolledStreak(at date: Date, calendar: Calendar = .current) -> (weeks: Int, counts: [Int]) {
        let generatedWeek = calendar.dateInterval(of: .weekOfYear, for: generatedAt)?.start ?? generatedAt
        let dateWeek = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        let elapsed = max(0, calendar.dateComponents([.weekOfYear], from: generatedWeek, to: dateWeek).weekOfYear ?? 0)
        guard elapsed > 0 else { return (streakWeeks, weeklyCounts) }
        let shifted = Array(weeklyCounts.dropFirst(min(elapsed, weeklyCounts.count)))
            + [Int](repeating: 0, count: min(elapsed, weeklyCounts.count))
        return (Self.streak(fromWeeklyCounts: shifted), shifted)
    }

    /// The streak rule, shared by the app-side writer and the widget's
    /// roll-forward: consecutive non-zero weeks ending now, except an
    /// empty CURRENT week defers to the run ending last week (it isn't
    /// over yet — Monday morning shouldn't read as a broken streak).
    static func streak(fromWeeklyCounts weeklyCounts: [Int]) -> Int {
        var streak = 0
        for count in weeklyCounts.reversed() {
            if count > 0 { streak += 1 } else { break }
        }
        if streak == 0, weeklyCounts.count >= 2, weeklyCounts.last == 0 {
            for count in weeklyCounts.dropLast().reversed() {
                if count > 0 { streak += 1 } else { break }
            }
        }
        return streak
    }

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
